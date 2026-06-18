import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { RelayRegistry } from "../src/registry.js";
import { MemoryDeliveryQueue } from "../src/queue.js";
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

function createSnapshotStore({
  type = "local_json",
  encrypted = true,
  snapshot = {}
} = {}) {
  let data = {
    records: [],
    twitchOAuthStates: [],
    deliveryAttempts: [],
    tokenRefreshAttempts: [],
    providerMessages: [],
    appReceipts: [],
    operations: {},
    ...snapshot
  };

  return {
    diagnostics: () => ({ type, encrypted }),
    snapshot: () => structuredClone(data),
    replace(next) {
      data = structuredClone(next);
    },
    flush() {}
  };
}

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
    assert.equal(JSON.stringify(payload).includes("client-secret"), false);
    assert.equal(JSON.stringify(payload).includes("private-key"), false);
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

routeTest("GET /ready enforces required field-level token encryption", async () => {
  const storage = {
    diagnostics: () => ({ type: "postgres_snapshot", encrypted: true }),
    snapshot: () => ({ records: [], twitchOAuthStates: [], deliveryAttempts: [] }),
    replace() {}
  };
  const { app: missingApp } = await makeRelayApp({
    registry: new RelayRegistry({ storage, secretEncryptionKey: null }),
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
      RELAY_REQUIRE_TOKEN_ENCRYPTION: "true"
    }
  });

  await withTestServer(missingApp, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready`);
    const payload = await response.json();

    assert.equal(response.status, 503);
    assert.equal(payload.ok, false);
    assert.equal(payload.checks.find((check) => check.name === "token_encryption").ok, false);
    assert.equal(JSON.stringify(payload).includes("private-key"), false);
  });

  const { app: readyApp } = await makeRelayApp({
    registry: new RelayRegistry({
      storage,
      secretEncryptionKey: Buffer.alloc(32, 11).toString("base64"),
      secretEncryptionKeyId: "test-key"
    }),
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
      RELAY_REQUIRE_TOKEN_ENCRYPTION: "true"
    }
  });

  await withTestServer(readyApp, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/ready`);
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.requireTokenEncryption, true);
    assert.equal(payload.secretEncryption.configured, true);
    assert.equal(payload.secretEncryption.keyId, "test-key");
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

routeTest("POST /v1/auth/apple creates a beta session without exposing Apple subject", async () => {
  const registry = new RelayRegistry();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env: {
      ...env,
      APPLE_AUTH_DEV_BYPASS: "true",
      NODE_ENV: "test"
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/auth/apple`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        identityToken: "apple-subject-1",
        fullName: "Streamer"
      })
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 201);
    assert.equal(payload.ok, true);
    assert.equal(typeof payload.sessionToken, "string");
    assert.equal(payload.account.provider, "apple");
    assert.equal(payload.account.hasProviderSubject, true);
    assert.equal(registry.getSession(payload.sessionToken).userId, payload.userId);
    assert.equal(serialized.includes("apple-subject-1"), false);
  });
});

routeTest("POST /v1/devices requires bearer auth and stores safe device metadata", async () => {
  const registry = new RelayRegistry();
  const account = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const { token } = registry.createSession({ userId: account.userId });
  const connectors = connectorManagerStub();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const unauthorized = await fetch(`${baseUrl}/v1/devices`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deviceToken: "1234567890123456" })
    });
    assert.equal(unauthorized.status, 401);

    const response = await fetch(`${baseUrl}/v1/devices`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({
        deviceToken: "1234567890123456",
        apnsEnvironment: "sandbox",
        appBuild: "100"
      })
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 201);
    assert.equal(payload.ok, true);
    assert.equal(payload.device.hasDeviceToken, true);
    assert.equal(payload.device.deviceTokenFingerprint.length, 12);
    assert.equal(payload.device.apnsEnvironment, "sandbox");
    assert.equal(registry.get(account.userId).deviceToken, "1234567890123456");
    assert.equal(serialized.includes("1234567890123456"), false);
    assert.deepEqual(connectors.syncedUsers, [account.userId]);
  });
});

routeTest("POST /v1/test-alert queues beta proof alerts with correlation IDs", async () => {
  const registry = new RelayRegistry();
  const account = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const { token } = registry.createSession({ userId: account.userId });
  registry.upsertDevice({
    userId: account.userId,
    deviceToken: "1234567890123456",
    apnsEnvironment: "sandbox"
  });
  const queue = new MemoryDeliveryQueue();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    deliveryQueue: queue,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/test-alert`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({
        type: "follow",
        username: "BetaProof"
      })
    });
    const payload = await response.json();

    assert.equal(response.status, 202);
    assert.equal(payload.ok, true);
    assert.equal(payload.queued, true);
    assert.equal(payload.correlationId.startsWith("proof:"), true);
    assert.equal(payload.attempt.status, "queued");
    assert.equal(await queue.length(), 1);

    const queuedJob = await queue.next();
    assert.equal(queuedJob.userId, account.userId);
    assert.equal(queuedJob.alert.correlationId, payload.correlationId);
  });
});

routeTest("GET /v1/diagnostics returns current-user safe diagnostics only", async () => {
  const registry = new RelayRegistry();
  const userOne = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const userTwo = registry.upsertAppleAccount({ appleSubject: "apple-subject-2" });
  const { token } = registry.createSession({ userId: userOne.userId });
  registry.recordDeliveryAttempt({
    userId: userOne.userId,
    alert: { correlationId: "proof:user-one", source: "twitch_native" },
    status: "sent",
    deviceToken: "secret-device-token-one"
  });
  registry.recordDeliveryAttempt({
    userId: userTwo.userId,
    alert: { correlationId: "proof:user-two", source: "twitch_native" },
    status: "sent",
    deviceToken: "secret-device-token-two"
  });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/diagnostics`, {
      headers: { "Authorization": `Bearer ${token}` }
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.user.userId, userOne.userId);
    assert.equal(payload.attempts.length, 1);
    assert.equal(payload.attempts[0].correlationId, "proof:user-one");
    assert.equal(serialized.includes("proof:user-two"), false);
    assert.equal(serialized.includes("secret-device-token-one"), false);
    assert.equal(serialized.includes("secret-device-token-two"), false);
  });
});

routeTest("POST /v1/alerts/receipt records app receipt and completes delivery trace", async () => {
  const registry = new RelayRegistry();
  const account = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const { token } = registry.createSession({ userId: account.userId });
  const alert = {
    correlationId: "twitch:message-1",
    providerMessageId: "message-1",
    source: "twitch_native",
    type: "follow"
  };
  registry.reserveProviderMessage({ userId: account.userId, alert });
  registry.recordDeliveryAttempt({
    userId: account.userId,
    alert,
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
    const response = await fetch(`${baseUrl}/v1/alerts/receipt`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`
      },
      body: JSON.stringify({
        correlationId: "twitch:message-1",
        providerMessageId: "message-1",
        appReceivedAt: "2026-06-18T10:00:00.000Z",
        appBuild: "100"
      })
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 201);
    assert.equal(payload.ok, true);
    assert.equal(payload.receipt.status, "received");
    assert.equal(payload.trace.stages.providerReceived, true);
    assert.equal(payload.trace.stages.apnsSent, true);
    assert.equal(payload.trace.stages.appReceived, true);
    assert.equal(serialized.includes("secret-device-token"), false);
  });
});

routeTest("GET /v1/diagnostics/trace scopes delivery traces to the authenticated user", async () => {
  const registry = new RelayRegistry();
  const userOne = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const userTwo = registry.upsertAppleAccount({ appleSubject: "apple-subject-2" });
  const { token } = registry.createSession({ userId: userOne.userId });
  registry.recordAppReceipt({
    userId: userOne.userId,
    correlationId: "proof:user-one"
  });
  registry.recordAppReceipt({
    userId: userTwo.userId,
    correlationId: "proof:user-two"
  });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/diagnostics/trace?correlationId=${encodeURIComponent("proof:user-one")}`,
      { headers: { "Authorization": `Bearer ${token}` } }
    );
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.trace.appReceipts.length, 1);
    assert.equal(payload.trace.stages.appReceived, true);
    assert.equal(serialized.includes("proof:user-two"), false);
  });
});

routeTest("POST /v1/twitch/disconnect removes Twitch credentials for the authenticated user", async () => {
  const registry = new RelayRegistry();
  const account = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const { token } = registry.createSession({ userId: account.userId });
  registry.setTwitchAuth({
    userId: account.userId,
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
  const connectors = connectorManagerStub();
  connectors.stoppedUsers = [];
  connectors.stopUser = (userId) => connectors.stoppedUsers.push(userId);
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/twitch/disconnect`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${token}` }
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(registry.get(account.userId).twitch, undefined);
    assert.deepEqual(registry.get(account.userId).credentials, []);
    assert.deepEqual(connectors.stoppedUsers, [account.userId]);
  });
});

routeTest("DELETE /v1/account removes the authenticated account and owned diagnostics", async () => {
  const registry = new RelayRegistry();
  const account = registry.upsertAppleAccount({ appleSubject: "apple-subject-1" });
  const { token } = registry.createSession({ userId: account.userId });
  registry.recordDeliveryAttempt({
    userId: account.userId,
    alert: { correlationId: "proof:delete-account", source: "twitch_native" },
    status: "sent"
  });
  const connectors = connectorManagerStub();
  connectors.stoppedUsers = [];
  connectors.stopUser = (userId) => connectors.stoppedUsers.push(userId);
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectors,
    env
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/account`, {
      method: "DELETE",
      headers: { "Authorization": `Bearer ${token}` }
    });
    const payload = await response.json();

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(registry.get(account.userId), undefined);
    assert.equal(registry.diagnostics().recentDeliveryAttempts.length, 0);
    assert.deepEqual(connectors.stoppedUsers, [account.userId]);
  });
});

routeTest("POST /internal/jobs/proof-check requires the internal token when configured", async () => {
  const { app } = await makeRelayApp({
    registry: new RelayRegistry({ storage: createSnapshotStore() }),
    logger,
    connectorManager: connectorManagerStub(),
    env: {
      ...env,
      RELAY_INTERNAL_TOKEN: "internal-token"
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/internal/jobs/proof-check`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subscriptionAudit: false })
    });
    const payload = await response.json();

    assert.equal(response.status, 401);
    assert.equal(payload.code, "RELAY_INTERNAL_TOKEN_REQUIRED");
  });
});

routeTest("POST /internal/jobs/proof-check reports operational readiness without secrets", async () => {
  const registry = new RelayRegistry({ storage: createSnapshotStore() });
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    env: {
      ...env,
      RELAY_INTERNAL_TOKEN: "internal-token",
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_BUNDLE_ID: "com.irlalert.app",
      APNS_PRIVATE_KEY: "private-key"
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/internal/jobs/proof-check`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-relay-internal-token": "internal-token"
      },
      body: JSON.stringify({ subscriptionAudit: false })
    });
    const payload = await response.json();
    const serialized = JSON.stringify(payload);

    assert.equal(response.status, 200);
    assert.equal(payload.ok, true);
    assert.equal(payload.checks.find((check) => check.name === "database_storage").ok, true);
    assert.equal(payload.checks.find((check) => check.name === "apns_configuration").ok, true);
    assert.equal(payload.recorded.status, "passed");
    assert.equal(serialized.includes("private-key"), false);
    assert.equal(serialized.includes("client-secret"), false);
    assert.equal(registry.diagnostics().operations.proofChecks[0].status, "passed");
  });
});

routeTest("POST /internal/jobs/proof-check fails queued delivery mode without a fresh worker heartbeat", async () => {
  const registry = new RelayRegistry({ storage: createSnapshotStore() });
  const queue = new MemoryDeliveryQueue();
  const { app } = await makeRelayApp({
    registry,
    logger,
    connectorManager: connectorManagerStub(),
    deliveryQueue: queue,
    env: {
      ...env,
      RELAY_INTERNAL_TOKEN: "internal-token",
      RELAY_DELIVERY_MODE: "queue",
      RELAY_REQUIRE_QUEUE: "true",
      APNS_KEY_ID: "key-id",
      APNS_TEAM_ID: "team-id",
      APNS_BUNDLE_ID: "com.irlalert.app",
      APNS_PRIVATE_KEY: "private-key"
    }
  });

  await withTestServer(app, async (baseUrl) => {
    const first = await fetch(`${baseUrl}/internal/jobs/proof-check`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-relay-internal-token": "internal-token"
      },
      body: JSON.stringify({ subscriptionAudit: false })
    });
    const firstPayload = await first.json();

    assert.equal(first.status, 503);
    assert.equal(firstPayload.checks.find((check) => check.name === "worker_heartbeat").ok, false);

    registry.recordWorkerHeartbeat({ workerId: "worker-1" });

    const second = await fetch(`${baseUrl}/internal/jobs/proof-check`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-relay-internal-token": "internal-token"
      },
      body: JSON.stringify({ subscriptionAudit: false })
    });
    const secondPayload = await second.json();

    assert.equal(second.status, 200);
    assert.equal(secondPayload.checks.find((check) => check.name === "worker_heartbeat").ok, true);
  });
});
