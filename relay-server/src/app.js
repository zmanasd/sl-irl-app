import express from "express";
import path from "path";
import pino from "pino";
import { apnsConfigDiagnostics, sendAlertPush } from "./apns.js";
import { RelayRegistry } from "./registry.js";
import { RelayConnectorManager } from "./connectors/manager.js";
import { TWITCH_EVENTSUB_SUBSCRIPTIONS } from "./connectors/twitch-subscriptions.js";
import { LocalJsonStore } from "./storage.js";
import {
  createTwitchOAuthStart,
  exchangeTwitchCode,
  fetchTwitchUser,
  refreshTwitchToken,
  twitchOAuthDiagnostics,
  twitchOAuthConfigFromEnv
} from "./twitch-oauth.js";

export function createLogger() {
  return pino({
    transport: {
      target: "pino-pretty",
      options: { colorize: true }
    }
  });
}

export function createDefaultRegistry(env = process.env) {
  const dataPath = env.RELAY_DATA_PATH
    ?? path.resolve("relay-server/.data/relay-store.json");
  const storage = new LocalJsonStore(dataPath);
  return new RelayRegistry({ storage });
}

export function createRelayApp({
  registry = createDefaultRegistry(),
  logger = createLogger(),
  sendAlert = sendAlertPush,
  connectorManager = null,
  env = process.env,
  fetchImpl = globalThis.fetch
} = {}) {
  const app = express();
  app.use(express.json({ limit: "1mb" }));

  const manager = connectorManager ?? new RelayConnectorManager({
    registry,
    logger,
    sendAlert
  });
  const mvpServices = new Set(["twitch_native"]);

  function storageDiagnostics() {
    return typeof registry.storage?.diagnostics === "function"
      ? registry.storage.diagnostics()
      : { type: "memory", encrypted: false };
  }

  async function syncUser(userId) {
    await manager.syncForUser(userId);
  }

  async function syncAllUsers() {
    if (typeof manager.syncAllUsers === "function") {
      return manager.syncAllUsers();
    }

    const results = [];
    const userIds = typeof registry.userIds === "function" ? registry.userIds() : [];
    for (const userId of userIds) {
      try {
        await syncUser(userId);
        results.push({ userId, ok: true });
      } catch (error) {
        results.push({ userId, ok: false, error: error?.message ?? "Connector sync failed." });
      }
    }
    return results;
  }

  function connectorRecoveryDiagnostics() {
    return typeof manager.recoveryDiagnostics === "function"
      ? manager.recoveryDiagnostics()
      : { lastSyncAllAt: null, syncedUsers: null, failedUsers: null, results: [] };
  }

  function relayReadiness() {
    const apns = apnsConfigDiagnostics(env);
    const twitchOAuth = twitchOAuthDiagnostics(env);
    const storage = storageDiagnostics();
    const requireEncryptedStorage = env.RELAY_REQUIRE_ENCRYPTED_STORAGE === "true";
    const checks = [
      {
        name: "apns",
        ok: apns.configured,
        missing: apns.missing
      },
      {
        name: "twitch_oauth",
        ok: twitchOAuth.configured,
        missing: twitchOAuth.missing
      },
      {
        name: "storage_encryption",
        ok: !requireEncryptedStorage || storage.encrypted === true,
        missing: requireEncryptedStorage && storage.encrypted !== true
          ? ["RELAY_STORAGE_ENCRYPTION_KEY"]
          : []
      }
    ];

    return {
      ok: checks.every((check) => check.ok),
      checks,
      readiness: { apns, twitchOAuth },
      storage,
      requireEncryptedStorage
    };
  }

  function userReadiness(userId) {
    const record = registry.get(userId);
    const connector = manager.diagnostics().find((item) => (
      item.userId === userId
      && item.service === "twitch_native"
    ));
    const requiredSubscriptionTypes = TWITCH_EVENTSUB_SUBSCRIPTIONS
      .filter((subscription) => !subscription.optionalForMvp)
      .map((subscription) => subscription.type);
    const subscriptionResults = Array.isArray(connector?.subscriptionResults)
      ? connector.subscriptionResults
      : [];
    const subscriptionByType = new Map(
      subscriptionResults.map((result) => [result.type, result])
    );
    const missingSubscriptions = requiredSubscriptionTypes.filter((type) => (
      subscriptionByType.get(type)?.ok !== true
    ));
    const failedSubscriptions = subscriptionResults
      .filter((result) => result.ok === false)
      .map((result) => ({
        type: result.type,
        status: result.status ?? null,
        error: result.error ?? null
      }));

    const checks = [
      {
        name: "registered_user",
        ok: Boolean(record),
        missing: record ? [] : ["user registration"]
      },
      {
        name: "device_token",
        ok: Boolean(record?.deviceToken),
        missing: record?.deviceToken ? [] : ["device token"]
      },
      {
        name: "twitch_oauth",
        ok: Boolean(record?.twitch?.accessToken && record?.twitch?.refreshToken),
        missing: record?.twitch?.accessToken && record?.twitch?.refreshToken
          ? []
          : ["Twitch OAuth tokens"]
      },
      {
        name: "twitch_eventsub",
        ok: Boolean(
          connector
          && connector.status === "session_ready"
          && connector.keepaliveStale !== true
          && missingSubscriptions.length === 0
          && failedSubscriptions.length === 0
        ),
        missing: connector
          ? [
              ...(connector.status === "session_ready" ? [] : [`connector status ${connector.status ?? "missing"}`]),
              ...(connector.keepaliveStale === true ? ["fresh keepalive"] : []),
              ...missingSubscriptions
            ]
          : ["Twitch connector"]
      }
    ];

    return {
      ok: checks.every((check) => check.ok),
      userId,
      checks,
      twitch: record?.twitch ? {
        broadcasterId: record.twitch.broadcasterId,
        login: record.twitch.login,
        displayName: record.twitch.displayName,
        expiresAt: record.twitch.expiresAt,
        scopes: record.twitch.scopes ?? []
      } : null,
      connector: connector ? {
        status: connector.status,
        keepaliveStale: connector.keepaliveStale,
        lastKeepaliveAt: connector.lastKeepaliveAt,
        lastNotificationAt: connector.lastNotificationAt,
        lastError: connector.lastError,
        subscriptionResults,
        missingSubscriptions,
        failedSubscriptions
      } : null
    };
  }

  async function refreshTwitchUserToken(userId) {
    const record = registry.get(userId);
    if (!record?.twitch?.refreshToken) {
      const error = new Error("Twitch refresh token not found for user.");
      error.code = "TWITCH_REFRESH_TOKEN_NOT_FOUND";
      throw error;
    }

    const tokenPayload = await refreshTwitchToken({
      refreshToken: record.twitch.refreshToken,
      config: twitchOAuthConfigFromEnv(env),
      fetchImpl
    });
    const updated = registry.updateTwitchToken({ userId, tokenPayload });
    const attempt = registry.recordTwitchTokenRefreshAttempt({
      userId,
      status: "refreshed",
      expiresAt: updated.twitch.expiresAt,
      scopes: updated.twitch.scopes
    });

    await syncUser(userId);
    logger.info({ userId }, "Twitch token refreshed.");

    return { updated, attempt };
  }

  async function refreshDueTwitchTokens({
    now = new Date(),
    refreshWindowMs = Number(env.TWITCH_TOKEN_REFRESH_WINDOW_SECONDS ?? 600) * 1000
  } = {}) {
    const records = registry.twitchRecordsNeedingRefresh({ now, refreshWindowMs });
    const results = [];

    for (const record of records) {
      try {
        const { updated, attempt } = await refreshTwitchUserToken(record.userId);
        results.push({
          ok: true,
          userId: record.userId,
          expiresAt: updated.twitch.expiresAt,
          scopes: updated.twitch.scopes,
          attempt
        });
      } catch (error) {
        const attempt = registry.recordTwitchTokenRefreshAttempt({
          userId: record.userId,
          status: "failed",
          expiresAt: record.twitch?.expiresAt ?? null,
          scopes: record.twitch?.scopes ?? [],
          error
        });
        logger.error({ userId: record.userId, error: error.message }, "Twitch token refresh failed.");
        results.push({
          ok: false,
          userId: record.userId,
          error: error.message,
          code: error.code,
          attempt
        });
      }
    }

    return results;
  }

  async function sendAlertForRecord({ userId, record, alert }) {
    const result = await sendAlert({
      deviceToken: record.deviceToken,
      alert
    });
    const attempt = registry.recordDeliveryAttempt({
      userId,
      alert,
      status: result.ok ? "sent" : "failed",
      result,
      deviceToken: record.deviceToken
    });

    return { ok: result.ok, result, attempt };
  }

  function filterMvpServices(services) {
    return Array.isArray(services)
      ? services.filter((service) => mvpServices.has(service))
      : [];
  }

  function filterMvpCredentials(credentials) {
    return Array.isArray(credentials)
      ? credentials.filter((credential) => mvpServices.has(credential?.service))
      : [];
  }

  app.get("/health", (_req, res) => {
    res.json({
      ok: true,
      users: registry.count(),
      pendingTwitchOAuthStates: registry.diagnostics().pendingTwitchOAuthStates,
      storage: storageDiagnostics(),
      connectorRecovery: connectorRecoveryDiagnostics(),
      readiness: {
        apns: apnsConfigDiagnostics(env),
        twitchOAuth: twitchOAuthDiagnostics(env)
      }
    });
  });

  app.get("/ready", (req, res) => {
    const userId = req.query.userId?.toString();
    const readiness = relayReadiness();
    const user = userId ? userReadiness(userId) : null;
    const ok = readiness.ok && (user?.ok ?? true);
    return res.status(ok ? 200 : 503).json({
      ...readiness,
      ok,
      user
    });
  });

  app.get("/diagnostics", (_req, res) => {
    res.json({
      ok: true,
      ...registry.diagnostics(),
      storage: storageDiagnostics(),
      connectorRecovery: connectorRecoveryDiagnostics(),
      readiness: {
        apns: apnsConfigDiagnostics(env),
        twitchOAuth: twitchOAuthDiagnostics(env)
      },
      connectors: manager.diagnostics()
    });
  });

  app.get("/diagnostics/attempts", (req, res) => {
    const correlationId = req.query.correlationId?.toString();
    const providerMessageId = req.query.providerMessageId?.toString();
    const userId = req.query.userId?.toString();

    if (!correlationId && !providerMessageId) {
      return res.status(400).json({
        error: "correlationId or providerMessageId is required."
      });
    }

    return res.json({
      ok: true,
      correlationId: correlationId ?? null,
      providerMessageId: providerMessageId ?? null,
      userId: userId ?? null,
      attempts: registry.findDeliveryAttempts({
        correlationId,
        providerMessageId,
        userId
      })
    });
  });

  app.get("/auth/twitch/start", (req, res) => {
    const userId = req.query.userId?.toString();
    const redirect = req.query.redirect === "true";

    try {
      const result = createTwitchOAuthStart({
        userId,
        config: twitchOAuthConfigFromEnv(env)
      });
      registry.saveTwitchOAuthState(result.pendingState);
      logger.info({ userId }, "Created Twitch OAuth start URL.");

      if (redirect) {
        return res.redirect(result.authUrl);
      }

      return res.json({
        ok: true,
        authUrl: result.authUrl,
        state: result.state,
        scope: result.scope
      });
    } catch (error) {
      const status = error.code === "USER_ID_REQUIRED" ? 400 : 500;
      logger.error({ error: error.message }, "Failed to start Twitch OAuth.");
      return res.status(status).json({ error: error.message, code: error.code });
    }
  });

  app.post("/auth/twitch/refresh", async (req, res) => {
    const { userId } = req.body ?? {};
    if (!userId) {
      return res.status(400).json({ error: "userId is required." });
    }

    try {
      const { updated, attempt } = await refreshTwitchUserToken(userId);
      return res.json({
        ok: true,
        userId,
        attempt,
        twitch: {
          broadcasterId: updated.twitch.broadcasterId,
          login: updated.twitch.login,
          expiresAt: updated.twitch.expiresAt,
          scopes: updated.twitch.scopes
        }
      });
    } catch (error) {
      logger.error({ userId, error: error.message }, "Twitch token refresh failed.");
      const status = error.code === "TWITCH_REFRESH_TOKEN_NOT_FOUND" ? 404 : 502;
      if (status !== 404) {
        registry.recordTwitchTokenRefreshAttempt({
          userId,
          status: "failed",
          error
        });
      }
      return res.status(status).json({ error: error.message, code: error.code });
    }
  });

  app.post("/auth/twitch/refresh-due", async (_req, res) => {
    const results = await refreshDueTwitchTokens();
    const failed = results.filter((result) => !result.ok);

    return res.status(failed.length > 0 ? 207 : 200).json({
      ok: failed.length === 0,
      refreshed: results.filter((result) => result.ok).length,
      failed: failed.length,
      results
    });
  });

  app.get("/auth/twitch/callback", async (req, res) => {
    const code = req.query.code?.toString();
    const state = req.query.state?.toString();

    if (!code || !state) {
      return res.status(400).json({ error: "code and state are required." });
    }

    const pendingState = registry.consumeTwitchOAuthState(state);
    if (!pendingState) {
      return res.status(400).json({ error: "Invalid or expired Twitch OAuth state." });
    }

    try {
      const config = twitchOAuthConfigFromEnv(env);
      const tokenPayload = await exchangeTwitchCode({ code, config, fetchImpl });
      const twitchUser = await fetchTwitchUser({
        accessToken: tokenPayload.access_token,
        config,
        fetchImpl
      });

      registry.setTwitchAuth({
        userId: pendingState.userId,
        twitchUser,
        tokenPayload,
        scopes: config.scopes
      });
      await syncUser(pendingState.userId);

      logger.info(
        { userId: pendingState.userId, twitchUserId: twitchUser.id },
        "Twitch OAuth completed."
      );

      return res.json({
        ok: true,
        userId: pendingState.userId,
        twitch: {
          broadcasterId: twitchUser.id,
          login: twitchUser.login,
          displayName: twitchUser.display_name ?? twitchUser.login
        }
      });
    } catch (error) {
      logger.error({ error: error.message }, "Twitch OAuth callback failed.");
      return res.status(502).json({ error: error.message, code: error.code });
    }
  });

  app.post("/register", async (req, res) => {
    const { userId, deviceToken, services, credentials } = req.body ?? {};
    if (!userId || !deviceToken) {
      return res.status(400).json({ error: "userId and deviceToken are required." });
    }

    registry.register({
      userId,
      deviceToken,
      services: filterMvpServices(services),
      credentials: filterMvpCredentials(credentials)
    });

    await syncUser(userId);
    logger.info({ userId }, "User registered for relay.");
    return res.json({ ok: true });
  });

  app.post("/alert", async (req, res) => {
    const { userId, alert } = req.body ?? {};
    if (!userId || !alert) {
      return res.status(400).json({ error: "userId and alert are required." });
    }

    const record = registry.get(userId);
    if (!record) {
      return res.status(404).json({ error: "user not registered" });
    }

    const delivery = await sendAlertForRecord({ userId, record, alert });

    return res.json({ ok: delivery.ok, result: delivery.result, attempt: delivery.attempt });
  });

  app.post("/soundalerts/webhook", async (req, res) => {
    return res.status(410).json({
      ok: false,
      error: "SoundAlerts is post-MVP. Use Twitch EventSub -> APNs proof path."
    });
  });

  return { app, registry, connectorManager: manager, refreshDueTwitchTokens, syncAllUsers };
}
