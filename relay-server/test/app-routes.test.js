import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { RelayRegistry } from "../src/registry.js";
import { withTestServer } from "./http-helper.js";

const require = createRequire(import.meta.url);
let hasRuntimeDeps = true;
try {
  require.resolve("express");
  require.resolve("@parse/node-apn");
} catch {
  hasRuntimeDeps = false;
}

async function makeRelayApp(options) {
  const { createRelayApp } = await import("../src/app.js");
  return createRelayApp(options);
}

const logger = {
  info() {},
  warn() {},
  error() {}
};

function connectorManagerStub() {
  return {
    syncedUsers: [],
    async syncForUser(userId) {
      this.syncedUsers.push(userId);
    },
    diagnostics() {
      return [{ key: "stub:twitch_native", service: "twitch_native", status: "stubbed" }];
    }
  };
}

function connectorManagerWithDiagnostics(diagnostics) {
  return {
    syncedUsers: [],
    async syncForUser(userId) {
      this.syncedUsers.push(userId);
    },
    diagnostics() {
      return diagnostics;
    },
    recoveryDiagnostics() {
      return { lastSyncAllAt: null, syncedUsers: 0, failedUsers: 0, results: [] };
    }
  };
}

const env = {
  TWITCH_CLIENT_ID: "client-id",
  TWITCH_CLIENT_SECRET: "client-secret",
  TWITCH_REDIRECT_URI: "http://localhost:3000/auth/twitch/callback"
};

const routeTest = hasRuntimeDeps
  ? test
  : (name, fn) => test(name, { skip: "relay runtime dependencies are not installed" }, fn);

routeTest("GET /auth/twitch/start returns an auth URL and stores pending state", async () => {
  const registry = new RelayRegistry();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/auth/twitch/start?userId=user-1`);
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(new URL(payload.authUrl).searchParams.get("state"), payload.state);
    assert.equal(registry.diagnostics().pendingTwitchOAuthStates, 1);
  });
});

routeTest("GET /diagnostics includes safe registry and connector diagnostics", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "secret-token",
    services: ["twitch_native"],
    credentials: []
  });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/diagnostics`);
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.storage.type, "memory");
    assert.equal(payload.storage.encrypted, false);
    assert.equal(payload.connectorRecovery.lastSyncAllAt, null);
    assert.equal(payload.connectorRecovery.results.length, 0);
    assert.equal(payload.users[0].hasDeviceToken, true);
    assert.equal(payload.users[0].deviceTokenLength, "secret-token".length);
    assert.equal(payload.users[0].deviceTokenFingerprint.length, 12);
    assert.equal(payload.readiness.apns.configured, false);
    assert.equal(payload.readiness.apns.hasPrivateKey, false);
    assert.equal(payload.readiness.twitchOAuth.configured, true);
    assert.equal(payload.readiness.twitchOAuth.hasClientSecret, true);
    assert.equal(payload.connectors[0].status, "stubbed");
    assert.equal(serialized.includes("secret-token"), false);
    assert.equal(serialized.includes("client-secret"), false);
  });
});

routeTest("GET /ready reports missing MVP readiness requirements", async () => {
  const { app } = await makeRelayApp({
    registry: new RelayRegistry(),
    logger,
    connectorManager: connectorManagerStub(),
    env: {}
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready`);
    const payload = await response.json();

    assert.equal(response.status, 503);
    assert.equal(payload.ok, false);
    assert.equal(payload.checks.find((check) => check.name === "apns").ok, false);
    assert.equal(payload.checks.find((check) => check.name === "twitch_oauth").ok, false);
    assert.equal(JSON.stringify(payload).includes("secret"), false);
  });
});

routeTest("GET /ready passes with configured APNs, Twitch OAuth, and required encrypted storage", async () => {
  const storage = {
    diagnostics: () => ({ type: "local_json", encrypted: true }),
    snapshot: () => ({ records: [], twitchOAuthStates: [], deliveryAttempts: [] }),
    replace() {}
  };
  const registry = new RelayRegistry({ storage });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env: {
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_BUNDLE_ID: "com.irlalert.app",
      APNS_PRIVATE_KEY: "private-key",
      TWITCH_CLIENT_ID: "client-id",
      TWITCH_CLIENT_SECRET: "client-secret",
      TWITCH_REDIRECT_URI: "http://localhost:3000/auth/twitch/callback",
      RELAY_REQUIRE_ENCRYPTED_STORAGE: "true"
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready`);
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.requireEncryptedStorage, true);
    assert.equal(payload.storage.encrypted, true);
    assert.equal(serialized.includes("private-key"), false);
    assert.equal(serialized.includes("client-secret"), false);
  });
});

routeTest("GET /ready with userId reports missing user proof requirements", async () => {
  const { app } = await makeRelayApp({
    registry: new RelayRegistry(),
    logger,
    connectorManager: connectorManagerStub(),
    env: {
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_BUNDLE_ID: "com.irlalert.app",
      APNS_PRIVATE_KEY: "private-key",
      ...env
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready?userId=user-1`);
    const payload = await response.json();

    assert.equal(response.status, 503);
    assert.equal(payload.ok, false);
    assert.equal(payload.user.ok, false);
    assert.equal(payload.user.checks.find((check) => check.name === "registered_user").ok, false);
    assert.equal(payload.user.checks.find((check) => check.name === "twitch_eventsub").ok, false);
  });
});

routeTest("GET /ready with userId passes only when device, Twitch OAuth, and EventSub are ready", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });
  registry.setTwitchAuth({
    userId: "user-1",
    twitchUser: {
      id: "1234",
      login: "streamer",
      display_name: "Streamer"
    },
    tokenPayload: {
      access_token: "access-token",
      refresh_token: "refresh-token",
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  const requiredSubscriptions = [
    "channel.follow",
    "channel.subscribe",
    "channel.subscription.gift",
    "channel.subscription.message",
    "channel.cheer",
    "channel.raid"
  ];
  const connectors = connectorManagerWithDiagnostics([
    {
      key: "user-1:twitch_native",
      userId: "user-1",
      service: "twitch_native",
      status: "session_ready",
      keepaliveStale: false,
      lastKeepaliveAt: "2026-06-17T00:00:00.000Z",
      subscriptionResults: requiredSubscriptions.map((type) => ({
        type,
        ok: true,
        status: 202
      }))
    }
  ]);

  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env: {
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_BUNDLE_ID: "com.irlalert.app",
      APNS_PRIVATE_KEY: "private-key",
      ...env
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready?userId=user-1`);
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.user.ok, true);
    assert.equal(payload.user.connector.status, "session_ready");
    assert.deepEqual(payload.user.connector.missingSubscriptions, []);
    assert.equal(serialized.includes("access-token"), false);
    assert.equal(serialized.includes("refresh-token"), false);
    assert.equal(serialized.includes("device-token"), false);
  });
});

routeTest("POST /register stores device and syncs connectors", async () => {
  const registry = new RelayRegistry();
  const connectors = connectorManagerStub();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "user-1",
        deviceToken: "device-token",
        services: ["twitch_native"],
        credentials: []
      })
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(registry.get("user-1").deviceToken, "device-token");
    assert.deepEqual(connectors.syncedUsers, ["user-1"]);
  });
});

routeTest("POST /register filters non-MVP services and credentials", async () => {
  const registry = new RelayRegistry();
  const connectors = connectorManagerStub();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "user-1",
        deviceToken: "device-token",
        services: ["twitch_native", "streamlabs", "sound_alerts"],
        credentials: [
          { service: "twitch_native", type: "oauth", value: "twitch-token" },
          { service: "streamlabs", type: "socket", value: "streamlabs-token" }
        ]
      })
    });
    const payload = await response.json();
    const record = registry.get("user-1");

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.deepEqual(record.services, ["twitch_native"]);
    assert.deepEqual(record.credentials, [
      { service: "twitch_native", type: "oauth", value: "twitch-token" }
    ]);
  });
});

routeTest("POST /alert sends alert and records delivery attempt", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env,
    sendAlert: async () => ({
      ok: true,
      apnsIds: ["apns-1"],
      summary: { sent: 1, failed: 0 }
    })
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/alert`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "user-1",
        alert: {
          correlationId: "twitch:msg-1",
          providerMessageId: "msg-1",
          source: "twitch_native",
          type: "follow"
        }
      })
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.attempt.status, "sent");
    assert.equal(payload.attempt.apnsIds[0], "apns-1");
    assert.equal(payload.attempt.deviceTokenLength, "device-token".length);
    assert.equal(payload.attempt.deviceTokenFingerprint.length, 12);
    assert.equal(registry.diagnostics().recentDeliveryAttempts[0].correlationId, "twitch:msg-1");
  });
});

routeTest("POST /soundalerts/webhook is closed for the Twitch-first MVP", async () => {
  const { app } = await makeRelayApp({
    registry: new RelayRegistry(),
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/soundalerts/webhook`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "user-1",
        alert: { source: "sound_alerts", type: "follow" }
      })
    });
    const payload = await response.json();

    assert.equal(response.status, 410);
    assert.equal(payload.ok, false);
    assert.equal(payload.error.includes("post-MVP"), true);
  });
});

routeTest("GET /diagnostics/attempts returns exact correlation lookup without secrets", async () => {
  const registry = new RelayRegistry();
  registry.recordDeliveryAttempt({
    userId: "user-1",
    alert: {
      correlationId: "twitch:msg-1",
      providerMessageId: "msg-1",
      source: "twitch_native",
      type: "follow"
    },
    status: "sent",
    result: {
      apnsIds: ["apns-1"],
      summary: { sent: 1, failed: 0 }
    },
    deviceToken: "secret-device-token"
  });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/diagnostics/attempts?correlationId=${encodeURIComponent("twitch:msg-1")}`
    );
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.attempts.length, 1);
    assert.equal(payload.attempts[0].providerMessageId, "msg-1");
    assert.equal(payload.attempts[0].deviceTokenFingerprint.length, 12);
    assert.equal(serialized.includes("secret-device-token"), false);
  });
});

routeTest("GET /diagnostics/attempts requires a correlation or provider ID", async () => {
  const { app } = await makeRelayApp({
    registry: new RelayRegistry(),
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/diagnostics/attempts`);
    const payload = await response.json();

    assert.equal(response.status, 400);
    assert.equal(payload.error, "correlationId or providerMessageId is required.");
  });
});

routeTest("POST /auth/twitch/refresh refreshes one user and records diagnostics", async () => {
  const registry = new RelayRegistry();
  registry.setTwitchAuth({
    userId: "user-1",
    twitchUser: {
      id: "1234",
      login: "streamer",
      display_name: "Streamer"
    },
    tokenPayload: {
      access_token: "old-access-token",
      refresh_token: "refresh-token",
      expires_in: 60,
      scope: ["bits:read"]
    },
    scopes: []
  });
  const connectors = connectorManagerStub();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env,
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://id.twitch.tv/oauth2/token");
      assert.equal(options.body.get("grant_type"), "refresh_token");
      assert.equal(options.body.get("refresh_token"), "refresh-token");
      return {
        ok: true,
        json: async () => ({
          access_token: "new-access-token",
          refresh_token: "new-refresh-token",
          expires_in: 3600,
          scope: ["bits:read"]
        })
      };
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/auth/twitch/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userId: "user-1" })
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.attempt.status, "refreshed");
    assert.equal(registry.get("user-1").twitch.accessToken, "new-access-token");
    assert.deepEqual(connectors.syncedUsers, ["user-1"]);
    assert.equal(registry.diagnostics().recentTokenRefreshAttempts[0].status, "refreshed");
    assert.equal(serialized.includes("new-access-token"), false);
    assert.equal(serialized.includes("new-refresh-token"), false);
  });
});

routeTest("POST /auth/twitch/refresh-due refreshes expiring users", async () => {
  const registry = new RelayRegistry();
  registry.setTwitchAuth({
    userId: "due-user",
    twitchUser: {
      id: "1234",
      login: "streamer",
      display_name: "Streamer"
    },
    tokenPayload: {
      access_token: "old-access-token",
      refresh_token: "refresh-token",
      expires_in: 60,
      scope: ["bits:read"]
    },
    scopes: []
  });
  registry.get("due-user").twitch.expiresAt = "2020-01-01T00:00:00.000Z";

  const connectors = connectorManagerStub();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env,
    fetchImpl: async () => ({
      ok: true,
      json: async () => ({
        access_token: "new-access-token",
        refresh_token: "new-refresh-token",
        expires_in: 3600,
        scope: ["bits:read"]
      })
    })
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/auth/twitch/refresh-due`, {
      method: "POST"
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.refreshed, 1);
    assert.equal(payload.failed, 0);
    assert.equal(payload.results[0].attempt.status, "refreshed");
    assert.deepEqual(connectors.syncedUsers, ["due-user"]);
  });
});

routeTest("GET /auth/twitch/callback exchanges token and stores Twitch auth", async () => {
  const registry = new RelayRegistry();
  const start = registry.saveTwitchOAuthState({
    userId: "user-1",
    state: "state-1",
    createdAt: "2026-06-14T00:00:00Z"
  });
  assert.equal(start, undefined);

  const connectors = connectorManagerStub();
  let callCount = 0;
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env,
    fetchImpl: async (url) => {
      callCount += 1;
      if (url === "https://id.twitch.tv/oauth2/token") {
        return {
          ok: true,
          json: async () => ({
            access_token: "access-token",
            refresh_token: "refresh-token",
            expires_in: 3600,
            scope: ["bits:read"]
          })
        };
      }
      if (url === "https://api.twitch.tv/helix/users") {
        return {
          ok: true,
          json: async () => ({
            data: [{ id: "1234", login: "streamer", display_name: "Streamer" }]
          })
        };
      }
      throw new Error(`Unexpected URL: ${url}`);
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/auth/twitch/callback?code=abc&state=state-1`);
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.twitch.broadcasterId, "1234");
    assert.equal(registry.get("user-1").twitch.login, "streamer");
    assert.deepEqual(connectors.syncedUsers, ["user-1"]);
    assert.equal(callCount, 2);
  });
});
