import express from "express";
import { rateLimit } from "express-rate-limit";
import path from "path";
import pino from "pino";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { apnsConfigDiagnostics, sendAlertPush } from "./apns.js";
import { RelayRegistry } from "./registry.js";
import { RelayConnectorManager } from "./connectors/manager.js";
import { TWITCH_EVENTSUB_SUBSCRIPTIONS } from "./connectors/twitch-subscriptions.js";
import { LocalJsonStore, createStoreFromEnv } from "./storage.js";
import { requireBetaSession, verifyAppleIdentityToken } from "./auth.js";
import { captureException } from "./observability.js";
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

export async function createDefaultRegistryAsync(env = process.env) {
  const storage = await createStoreFromEnv(env);
  return new RelayRegistry({ storage });
}

export function createRelayApp({
  registry = createDefaultRegistry(),
  logger = createLogger(),
  sendAlert = sendAlertPush,
  connectorManager = null,
  deliveryQueue = null,
  env = process.env,
  fetchImpl = globalThis.fetch
} = {}) {
  const app = express();
  app.set("trust proxy", 1);
  app.use(express.json({ limit: "1mb" }));
  app.use((req, res, next) => {
    req.relayRequestId = req.get("x-request-id") || randomUUID();
    res.set("x-request-id", req.relayRequestId);
    const startedAt = Date.now();
    res.on("finish", () => {
      logger.info?.({
        requestId: req.relayRequestId,
        method: req.method,
        path: req.path,
        statusCode: res.statusCode,
        durationMs: Date.now() - startedAt,
        correlationId: req.body?.correlationId ?? req.query?.correlationId ?? null
      }, "Relay request completed.");
    });
    next();
  });
  app.use("/v1", rateLimit({
    windowMs: Number(env.RATE_LIMIT_WINDOW_MS ?? 60_000),
    limit: Number(env.RATE_LIMIT_MAX ?? 120),
    standardHeaders: true,
    legacyHeaders: false
  }));

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

  async function queueDiagnostics() {
    if (!deliveryQueue || typeof deliveryQueue.diagnostics !== "function") {
      return {
        type: "none",
        pending: 0
      };
    }
    return deliveryQueue.diagnostics();
  }

  function betaRuntimeDiagnostics() {
    return {
      environment: env.RELAY_ENVIRONMENT ?? env.NODE_ENV ?? "development",
      deliveryMode: env.RELAY_DELIVERY_MODE ?? "inline",
      publicApi: "v1",
      internalAuthConfigured: Boolean(env.RELAY_INTERNAL_TOKEN),
      sentryConfigured: Boolean(env.SENTRY_DSN)
    };
  }

  function reportError(error, message, context = {}) {
    logger.error?.({ ...context, error: error?.message }, message);
    captureException(error, {
      ...context,
      message
    });
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

  async function relayReadiness() {
    const apns = apnsConfigDiagnostics(env);
    const twitchOAuth = twitchOAuthDiagnostics(env);
    const storage = storageDiagnostics();
    const secretEncryption = registry.diagnostics().secretEncryption ?? {
      configured: false,
      missing: ["RELAY_TOKEN_ENCRYPTION_KEY"]
    };
    const requireEncryptedStorage = env.RELAY_REQUIRE_ENCRYPTED_STORAGE === "true";
    const requireTokenEncryption = env.RELAY_REQUIRE_TOKEN_ENCRYPTION === "true";
    const queue = await queueDiagnostics();
    const requireQueue = env.RELAY_REQUIRE_QUEUE === "true";
    const requireAppleAuth = env.RELAY_REQUIRE_APPLE_AUTH === "true";
    const hasAppleAuth = Boolean(env.APPLE_AUTH_DEV_BYPASS === "true" || env.APPLE_CLIENT_ID || env.APNS_BUNDLE_ID);
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
      },
      {
        name: "token_encryption",
        ok: !requireTokenEncryption || secretEncryption.configured === true,
        missing: requireTokenEncryption && secretEncryption.configured !== true
          ? secretEncryption.missing ?? ["RELAY_TOKEN_ENCRYPTION_KEY"]
          : []
      },
      {
        name: "delivery_queue",
        ok: !requireQueue || queue.type !== "none",
        missing: requireQueue && queue.type === "none" ? ["REDIS_URL or RELAY_QUEUE_DRIVER"] : []
      },
      {
        name: "apple_auth",
        ok: !requireAppleAuth || hasAppleAuth,
        missing: requireAppleAuth && !hasAppleAuth ? ["APPLE_CLIENT_ID or APNS_BUNDLE_ID"] : []
      }
    ];

    return {
      ok: checks.every((check) => check.ok),
      checks,
      readiness: { apns, twitchOAuth },
      storage,
      secretEncryption,
      queue,
      runtime: betaRuntimeDiagnostics(),
      requireEncryptedStorage,
      requireTokenEncryption
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

  async function sendAlertForRecord({ userId, record, alert, preferQueue = false }) {
    if (preferQueue && deliveryQueue) {
      const job = await deliveryQueue.enqueue({ userId, alert });
      const attempt = registry.recordDeliveryAttempt({
        userId,
        alert,
        status: "queued",
        result: {
          ok: true,
          queued: true,
          jobId: job.id,
          summary: { sent: 0, failed: 0 }
        },
        deviceToken: record.deviceToken
      });
      await registry.flush?.();

      return {
        ok: true,
        queued: true,
        job,
        result: { ok: true, queued: true, jobId: job.id },
        attempt
      };
    }

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
    await registry.flush?.();

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

  function internalAuth(req, res, next) {
    if (!env.RELAY_INTERNAL_TOKEN && env.RELAY_ENVIRONMENT !== "production-beta") {
      return next();
    }

    const token = req.get("x-relay-internal-token");
    if (token && token === env.RELAY_INTERNAL_TOKEN) {
      return next();
    }

    return res.status(401).json({
      error: "A valid internal relay token is required.",
      code: "RELAY_INTERNAL_TOKEN_REQUIRED"
    });
  }

  function validate(schema, body) {
    const result = schema.safeParse(body ?? {});
    if (!result.success) {
      const error = new Error("Invalid request body.");
      error.code = "VALIDATION_FAILED";
      error.issues = result.error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message
      }));
      throw error;
    }
    return result.data;
  }

  function safeCurrentUser(userId) {
    const diagnostics = registry.diagnostics();
    return diagnostics.users.find((user) => user.userId === userId) ?? null;
  }

  function buildSyntheticAlert({ type = "follow", username = "RelayProof", message = "Private beta proof alert" } = {}) {
    const id = randomUUID();
    const correlationId = `proof:${id}`;
    return {
      correlationId,
      providerMessageId: `proof-${id}`,
      alert_id: `proof-${id}`,
      type,
      username,
      message,
      amount: null,
      formatted_amount: null,
      sound_url: null,
      timestamp: new Date().toISOString(),
      source: "twitch_native"
    };
  }

  function latestWorkerHeartbeat() {
    const heartbeats = registry.diagnostics().operations?.workerHeartbeats ?? {};
    return Object.values(heartbeats)
      .filter((heartbeat) => heartbeat?.createdAt)
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] ?? null;
  }

  function workerHeartbeatProofCheck() {
    const deliveryMode = env.RELAY_DELIVERY_MODE ?? "inline";
    const heartbeat = latestWorkerHeartbeat();
    const maxAgeSeconds = Number(env.RELAY_WORKER_HEARTBEAT_MAX_AGE_SECONDS ?? 120);
    const heartbeatAgeSeconds = heartbeat?.createdAt
      ? Math.round((Date.now() - Date.parse(heartbeat.createdAt)) / 1000)
      : null;
    const required = deliveryMode === "queue" || env.RELAY_REQUIRE_WORKER_HEARTBEAT === "true";

    return {
      name: "worker_heartbeat",
      category: "worker",
      ok: !required || (heartbeatAgeSeconds !== null && heartbeatAgeSeconds <= maxAgeSeconds),
      required,
      maxAgeSeconds,
      heartbeatAgeSeconds,
      heartbeat
    };
  }

  async function runOperationalProofCheck({
    userId = null,
    sendProofAlert = false,
    subscriptionAudit = false
  } = {}) {
    const readiness = await relayReadiness();
    const storage = storageDiagnostics();
    const queue = await queueDiagnostics();
    const requireQueue = env.RELAY_REQUIRE_QUEUE === "true";
    const checks = [
      {
        name: "database_storage",
        category: "database",
        ok: env.RELAY_ENVIRONMENT === "production-beta"
          ? storage.type === "postgres_snapshot"
          : storage.type !== "memory",
        storage
      },
      {
        name: "delivery_queue",
        category: "queue",
        ok: !requireQueue || queue.type !== "none",
        queue
      },
      workerHeartbeatProofCheck(),
      {
        name: "apns_configuration",
        category: "apns",
        ok: readiness.readiness.apns.configured,
        missing: readiness.readiness.apns.missing
      },
      {
        name: "twitch_oauth_configuration",
        category: "twitch_oauth",
        ok: readiness.readiness.twitchOAuth.configured,
        missing: readiness.readiness.twitchOAuth.missing
      },
      {
        name: "readiness_gate",
        category: "configuration",
        ok: readiness.ok,
        checks: readiness.checks
      }
    ];

    let audit = null;
    if (subscriptionAudit) {
      const results = await syncAllUsers();
      const failed = results.filter((result) => !result.ok);
      audit = {
        ok: failed.length === 0,
        synced: results.length - failed.length,
        failed: failed.length,
        results
      };
      checks.push({
        name: "twitch_subscription_audit",
        category: "twitch_eventsub",
        ok: audit.ok,
        synced: audit.synced,
        failed: audit.failed
      });
    }

    let user = null;
    let proofAlert = null;
    if (userId) {
      user = userReadiness(userId);
      checks.push({
        name: "user_readiness",
        category: "app_device",
        ok: user.ok,
        checks: user.checks
      });
    }

    if (sendProofAlert) {
      if (!userId) {
        checks.push({
          name: "synthetic_alert",
          category: "apns",
          ok: false,
          error: "userId is required when sendProofAlert is true."
        });
      } else {
        const record = registry.get(userId);
        if (!record) {
          checks.push({
            name: "synthetic_alert",
            category: "apns",
            ok: false,
            error: "user not registered"
          });
        } else {
          const alert = buildSyntheticAlert({
            username: "OpsProof",
            message: "Private beta operational proof alert"
          });
          const delivery = await sendAlertForRecord({
            userId,
            record,
            alert,
            preferQueue: Boolean(deliveryQueue)
          });
          proofAlert = {
            ok: delivery.ok,
            queued: delivery.queued === true,
            correlationId: alert.correlationId,
            providerMessageId: alert.providerMessageId,
            attempt: delivery.attempt ?? null,
            result: delivery.result ?? null
          };
          checks.push({
            name: "synthetic_alert",
            category: "apns",
            ok: delivery.ok === true,
            queued: delivery.queued === true,
            correlationId: alert.correlationId
          });
        }
      }
    }

    const ok = checks.every((check) => check.ok);
    const recorded = registry.recordProofCheck({
      status: ok ? "passed" : "failed",
      checks,
      userId,
      correlationId: proofAlert?.correlationId ?? null
    });
    await registry.flush?.();

    return {
      ok,
      recorded,
      checks,
      readiness,
      storage,
      queue,
      worker: workerHeartbeatProofCheck(),
      audit,
      user,
      proofAlert
    };
  }

  const appleAuthSchema = z.object({
    identityToken: z.string().min(1),
    fullName: z.string().min(1).max(200).optional().nullable()
  });
  const deviceSchema = z.object({
    deviceToken: z.string().min(16),
    apnsEnvironment: z.enum(["sandbox", "production"]).optional().nullable(),
    appBuild: z.string().max(80).optional().nullable(),
    appVersion: z.string().max(80).optional().nullable()
  });
  const testAlertSchema = z.object({
    type: z.string().min(1).max(60).optional(),
    username: z.string().min(1).max(100).optional(),
    message: z.string().min(1).max(300).optional()
  });
  const preferencesSchema = z.object({
    alertsEnabled: z.boolean().optional(),
    soundEnabled: z.boolean().optional(),
    ttsEnabled: z.boolean().optional(),
    minimumBits: z.number().int().min(0).max(1_000_000).optional()
  }).strict();
  const appReceiptSchema = z.object({
    correlationId: z.string().min(1),
    providerMessageId: z.string().min(1).optional().nullable(),
    status: z.enum(["received", "dropped"]).optional(),
    appReceivedAt: z.string().min(1).optional().nullable(),
    appBuild: z.string().max(80).optional().nullable(),
    appVersion: z.string().max(80).optional().nullable()
  });

  const betaSession = requireBetaSession({ registry });

  app.get("/health", async (_req, res) => {
    res.json({
      ok: true,
      users: registry.count(),
      pendingTwitchOAuthStates: registry.diagnostics().pendingTwitchOAuthStates,
      storage: storageDiagnostics(),
      queue: await queueDiagnostics(),
      runtime: betaRuntimeDiagnostics(),
      connectorRecovery: connectorRecoveryDiagnostics(),
      readiness: {
        apns: apnsConfigDiagnostics(env),
        twitchOAuth: twitchOAuthDiagnostics(env)
      }
    });
  });

  app.get("/ready", async (req, res) => {
    const userId = req.query.userId?.toString();
    const readiness = await relayReadiness();
    const user = userId ? userReadiness(userId) : null;
    const ok = readiness.ok && (user?.ok ?? true);
    return res.status(ok ? 200 : 503).json({
      ...readiness,
      ok,
      user
    });
  });

  app.get("/diagnostics", async (_req, res) => {
    res.json({
      ok: true,
      ...registry.diagnostics(),
      storage: storageDiagnostics(),
      queue: await queueDiagnostics(),
      runtime: betaRuntimeDiagnostics(),
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
      }),
      trace: registry.deliveryTrace({
        correlationId,
        providerMessageId,
        userId
      })
    });
  });

  async function completeTwitchOAuthCallback(req, res) {
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
      await registry.flush?.();
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
  }

  app.post("/v1/auth/apple", async (req, res) => {
    try {
      const body = validate(appleAuthSchema, req.body);
      const apple = await verifyAppleIdentityToken({
        identityToken: body.identityToken,
        env
      });
      const record = registry.upsertAppleAccount({
        appleSubject: apple.subject,
        email: apple.email,
        fullName: body.fullName
      });
      const { token, session } = registry.createSession({
        userId: record.userId,
        ttlSeconds: Number(env.RELAY_SESSION_TTL_SECONDS ?? 60 * 60 * 24 * 30)
      });
      await registry.flush?.();

      return res.status(201).json({
        ok: true,
        userId: record.userId,
        sessionToken: token,
        session,
        account: safeCurrentUser(record.userId)?.account ?? null
      });
    } catch (error) {
      const status = error.code === "VALIDATION_FAILED" ? 400 : 401;
      return res.status(status).json({
        error: error.message,
        code: error.code,
        issues: error.issues
      });
    }
  });

  app.get("/v1/twitch/oauth/start", betaSession, async (req, res) => {
    const redirect = req.query.redirect === "true";

    try {
      const result = createTwitchOAuthStart({
        userId: req.relayUserId,
        config: twitchOAuthConfigFromEnv(env)
      });
      registry.saveTwitchOAuthState(result.pendingState);
      await registry.flush?.();
      logger.info({ userId: req.relayUserId }, "Created Twitch OAuth start URL.");

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

  app.get("/v1/twitch/oauth/callback", completeTwitchOAuthCallback);

  app.post("/v1/devices", betaSession, async (req, res) => {
    try {
      const body = validate(deviceSchema, req.body);
      const device = registry.upsertDevice({
        userId: req.relayUserId,
        ...body
      });
      await registry.flush?.();
      await syncUser(req.relayUserId);
      return res.status(201).json({ ok: true, device });
    } catch (error) {
      return res.status(400).json({
        error: error.message,
        code: error.code,
        issues: error.issues
      });
    }
  });

  app.delete("/v1/devices/:id", betaSession, async (req, res) => {
    const removed = registry.removeDevice({
      userId: req.relayUserId,
      deviceId: req.params.id
    });
    await registry.flush?.();
    return res.status(removed ? 200 : 404).json({ ok: removed });
  });

  app.get("/v1/status", betaSession, async (req, res) => {
    const readiness = await relayReadiness();
    const user = userReadiness(req.relayUserId);
    return res.status(readiness.ok && user.ok ? 200 : 503).json({
      ok: readiness.ok && user.ok,
      readiness,
      user,
      account: safeCurrentUser(req.relayUserId)
    });
  });

  app.get("/v1/diagnostics", betaSession, async (req, res) => {
    const diagnostics = registry.diagnostics();
    return res.json({
      ok: true,
      user: safeCurrentUser(req.relayUserId),
      attempts: diagnostics.recentDeliveryAttempts
        .filter((attempt) => attempt.userId === req.relayUserId),
      tokenRefreshAttempts: diagnostics.recentTokenRefreshAttempts
        .filter((attempt) => attempt.userId === req.relayUserId),
      readiness: await relayReadiness(),
      userReadiness: userReadiness(req.relayUserId),
      queue: await queueDiagnostics(),
      connectors: manager.diagnostics()
        .filter((connector) => connector.userId === req.relayUserId)
    });
  });

  app.get("/v1/diagnostics/trace", betaSession, (req, res) => {
    const correlationId = req.query.correlationId?.toString();
    const providerMessageId = req.query.providerMessageId?.toString();

    if (!correlationId && !providerMessageId) {
      return res.status(400).json({
        error: "correlationId or providerMessageId is required."
      });
    }

    return res.json({
      ok: true,
      correlationId: correlationId ?? null,
      providerMessageId: providerMessageId ?? null,
      trace: registry.deliveryTrace({
        correlationId,
        providerMessageId,
        userId: req.relayUserId
      })
    });
  });

  app.post("/v1/alerts/receipt", betaSession, async (req, res) => {
    try {
      const body = validate(appReceiptSchema, req.body);
      const receipt = registry.recordAppReceipt({
        userId: req.relayUserId,
        ...body,
        status: body.status ?? "received"
      });
      await registry.flush?.();
      return res.status(201).json({
        ok: true,
        receipt,
        trace: registry.deliveryTrace({
          correlationId: body.correlationId,
          providerMessageId: body.providerMessageId,
          userId: req.relayUserId
        })
      });
    } catch (error) {
      return res.status(400).json({
        error: error.message,
        code: error.code,
        issues: error.issues
      });
    }
  });

  app.post("/v1/test-alert", betaSession, async (req, res) => {
    try {
      const body = validate(testAlertSchema, req.body);
      const record = registry.get(req.relayUserId);
      if (!record) {
        return res.status(404).json({ error: "user not registered" });
      }

      const alert = buildSyntheticAlert(body);
      const delivery = await sendAlertForRecord({
        userId: req.relayUserId,
        record,
        alert,
        preferQueue: Boolean(deliveryQueue)
      });
      return res.status(delivery.queued ? 202 : 200).json({
        ok: delivery.ok,
        queued: delivery.queued === true,
        correlationId: alert.correlationId,
        providerMessageId: alert.providerMessageId,
        result: delivery.result,
        attempt: delivery.attempt
      });
    } catch (error) {
      return res.status(400).json({
        error: error.message,
        code: error.code,
        issues: error.issues
      });
    }
  });

  app.patch("/v1/preferences", betaSession, async (req, res) => {
    try {
      const preferences = validate(preferencesSchema, req.body);
      const updated = registry.updatePreferences({
        userId: req.relayUserId,
        preferences
      });
      await registry.flush?.();
      return res.json({ ok: true, preferences: updated });
    } catch (error) {
      return res.status(400).json({
        error: error.message,
        code: error.code,
        issues: error.issues
      });
    }
  });

  app.post("/v1/twitch/disconnect", betaSession, async (_req, res) => {
    manager.stopUser?.(_req.relayUserId);
    const record = registry.disconnectTwitch(_req.relayUserId);
    await registry.flush?.();
    return res.json({ ok: Boolean(record), user: safeCurrentUser(_req.relayUserId) });
  });

  app.delete("/v1/account", betaSession, async (req, res) => {
    manager.stopUser?.(req.relayUserId);
    const deleted = registry.deleteAccount(req.relayUserId);
    await registry.flush?.();
    return res.json({ ok: deleted });
  });

  app.post("/internal/jobs/proof-alert", internalAuth, async (req, res) => {
    const userId = req.body?.userId?.toString();
    if (!userId) {
      return res.status(400).json({ error: "userId is required." });
    }

    const record = registry.get(userId);
    if (!record) {
      return res.status(404).json({ error: "user not registered" });
    }

    const alert = buildSyntheticAlert({
      username: "InternalProof",
      message: "Scheduled private beta proof alert"
    });
    const delivery = await sendAlertForRecord({
      userId,
      record,
      alert,
      preferQueue: Boolean(deliveryQueue)
    });
    return res.status(delivery.queued ? 202 : 200).json({
      ok: delivery.ok,
      queued: delivery.queued === true,
      correlationId: alert.correlationId,
      providerMessageId: alert.providerMessageId,
      attempt: delivery.attempt,
      result: delivery.result
    });
  });

  app.post("/internal/twitch/subscription-audit", internalAuth, async (_req, res) => {
    const results = await syncAllUsers();
    const failed = results.filter((result) => !result.ok);
    return res.status(failed.length > 0 ? 207 : 200).json({
      ok: failed.length === 0,
      synced: results.length - failed.length,
      failed: failed.length,
      results,
      connectors: manager.diagnostics()
    });
  });

  app.post("/internal/jobs/proof-check", internalAuth, async (req, res) => {
    try {
      const result = await runOperationalProofCheck({
        userId: req.body?.userId?.toString() || env.RELAY_PROOF_USER_ID || null,
        sendProofAlert: req.body?.sendProofAlert === true || env.RELAY_PROOF_SEND_ALERT === "true",
        subscriptionAudit: req.body?.subscriptionAudit !== false
      });
      return res.status(result.ok ? 200 : 503).json(result);
    } catch (error) {
      reportError(error, "Operational proof check failed.", {
        requestId: req.relayRequestId
      });
      return res.status(500).json({
        ok: false,
        error: error.message,
        code: error.code
      });
    }
  });

  app.get("/auth/twitch/start", async (req, res) => {
    const userId = req.query.userId?.toString();
    const redirect = req.query.redirect === "true";

    try {
      const result = createTwitchOAuthStart({
        userId,
        config: twitchOAuthConfigFromEnv(env)
      });
      registry.saveTwitchOAuthState(result.pendingState);
      await registry.flush?.();
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

  app.get("/auth/twitch/callback", completeTwitchOAuthCallback);

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
    await registry.flush?.();

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

    const delivery = await sendAlertForRecord({
      userId,
      record,
      alert,
      preferQueue: env.RELAY_DELIVERY_MODE === "queue"
    });

    return res
      .status(delivery.queued ? 202 : 200)
      .json({ ok: delivery.ok, queued: delivery.queued === true, result: delivery.result, attempt: delivery.attempt });
  });

  app.post("/soundalerts/webhook", async (req, res) => {
    return res.status(410).json({
      ok: false,
      error: "SoundAlerts is post-MVP. Use Twitch EventSub -> APNs proof path."
    });
  });

  return { app, registry, connectorManager: manager, refreshDueTwitchTokens, syncAllUsers };
}
