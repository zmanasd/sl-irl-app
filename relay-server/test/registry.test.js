import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { RelayRegistry, deviceTokenDiagnostics } from "../src/registry.js";
import { LocalJsonStore, createEncryptedSnapshot, readEncryptedSnapshot } from "../src/storage.js";

function tempStorePath() {
  return path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "irlalert-registry-")),
    "store.json"
  );
}

test("persists device registrations", () => {
  const storePath = tempStorePath();
  const registry = new RelayRegistry({ storage: new LocalJsonStore(storePath) });

  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });

  const reloaded = new RelayRegistry({ storage: new LocalJsonStore(storePath) });
  assert.equal(reloaded.get("user-1").deviceToken, "device-token");
  assert.deepEqual(reloaded.get("user-1").services, ["twitch_native"]);
  assert.deepEqual(reloaded.userIds(), ["user-1"]);
});

test("encrypts local JSON storage when a 32-byte key is configured", () => {
  const storePath = tempStorePath();
  const encryptionKey = Buffer.alloc(32, 7).toString("base64");
  const registry = new RelayRegistry({
    storage: new LocalJsonStore(storePath, { encryptionKey })
  });

  registry.register({
    userId: "user-1",
    deviceToken: "secret-device-token",
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
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token",
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  const raw = fs.readFileSync(storePath, "utf8");
  assert.equal(raw.includes("secret-device-token"), false);
  assert.equal(raw.includes("secret-access-token"), false);
  assert.equal(raw.includes("secret-refresh-token"), false);
  assert.equal(JSON.parse(raw).encrypted, true);

  const reloaded = new RelayRegistry({
    storage: new LocalJsonStore(storePath, { encryptionKey })
  });
  assert.equal(reloaded.get("user-1").deviceToken, "secret-device-token");
  assert.equal(reloaded.get("user-1").twitch.accessToken, "secret-access-token");
});

test("encrypted snapshots require the correct storage key", () => {
  const encryptionKey = Buffer.alloc(32, 3).toString("base64");
  const wrongKey = Buffer.alloc(32, 4).toString("base64");
  const snapshot = createEncryptedSnapshot({
    data: { records: [{ userId: "user-1" }] },
    key: encryptionKey,
    iv: Buffer.alloc(12, 5)
  });

  assert.equal(snapshot.encrypted, true);
  assert.equal(readEncryptedSnapshot({ payload: snapshot, key: encryptionKey }).records[0].userId, "user-1");
  assert.throws(
    () => readEncryptedSnapshot({ payload: snapshot, key: wrongKey }),
    /Unsupported state|unable to authenticate|bad decrypt/
  );
});

test("field-level secret encryption protects OAuth, Apple, and device tokens at rest", () => {
  const storePath = tempStorePath();
  const secretEncryptionKey = Buffer.alloc(32, 9).toString("base64");
  const registry = new RelayRegistry({
    storage: new LocalJsonStore(storePath),
    secretEncryptionKey,
    secretEncryptionKeyId: "test-key"
  });

  const account = registry.upsertAppleAccount({
    appleSubject: "secret-apple-subject",
    email: "streamer@example.com",
    fullName: "Streamer"
  });
  registry.register({
    userId: account.userId,
    deviceToken: "secret-device-token",
    services: ["twitch_native"],
    credentials: []
  });
  registry.setTwitchAuth({
    userId: account.userId,
    twitchUser: {
      id: "1234",
      login: "streamer",
      display_name: "Streamer"
    },
    tokenPayload: {
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token",
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  const raw = fs.readFileSync(storePath, "utf8");
  assert.equal(raw.includes("secret-device-token"), false);
  assert.equal(raw.includes("secret-access-token"), false);
  assert.equal(raw.includes("secret-refresh-token"), false);
  assert.equal(raw.includes("secret-apple-subject"), false);
  assert.equal(raw.includes("streamer@example.com"), false);
  assert.equal(raw.includes("relay_secret"), true);
  assert.equal(raw.includes("test-key"), true);

  const reloaded = new RelayRegistry({
    storage: new LocalJsonStore(storePath),
    secretEncryptionKey
  });
  assert.equal(reloaded.get(account.userId).deviceToken, "secret-device-token");
  assert.equal(reloaded.get(account.userId).twitch.accessToken, "secret-access-token");
  assert.equal(reloaded.get(account.userId).twitch.refreshToken, "secret-refresh-token");
  assert.equal(reloaded.get(account.userId).account.providerSubject, "secret-apple-subject");
  assert.equal(reloaded.get(account.userId).account.email, "streamer@example.com");
});

test("encrypted relay secrets require the token encryption key on reload", () => {
  const storePath = tempStorePath();
  const secretEncryptionKey = Buffer.alloc(32, 10).toString("base64");
  const registry = new RelayRegistry({
    storage: new LocalJsonStore(storePath),
    secretEncryptionKey
  });

  registry.register({
    userId: "user-1",
    deviceToken: "secret-device-token",
    services: ["twitch_native"],
    credentials: []
  });

  assert.throws(
    () => new RelayRegistry({ storage: new LocalJsonStore(storePath), secretEncryptionKey: null }),
    /RELAY_TOKEN_ENCRYPTION_KEY is required/
  );
});

test("stores and consumes Twitch OAuth states once", () => {
  const registry = new RelayRegistry();
  registry.saveTwitchOAuthState({
    state: "state-1",
    userId: "user-1",
    createdAt: "2026-06-14T00:00:00Z"
  });

  assert.equal(registry.consumeTwitchOAuthState("state-1").userId, "user-1");
  assert.equal(registry.consumeTwitchOAuthState("state-1"), null);
});

test("creates Apple accounts and bearer sessions without exposing session tokens", () => {
  const registry = new RelayRegistry();
  const record = registry.upsertAppleAccount({
    appleSubject: "apple-user-1",
    email: "streamer@example.com",
    fullName: "Streamer"
  });
  const { token, session } = registry.createSession({ userId: record.userId });

  assert.equal(record.account.provider, "apple");
  assert.equal(typeof token, "string");
  assert.equal(registry.getSession(token).userId, record.userId);
  assert.equal(registry.getSession("wrong-token"), null);
  assert.equal(session.id.startsWith("session_"), true);
  assert.equal(JSON.stringify(registry.diagnostics()).includes(token), false);
  assert.equal(JSON.stringify(registry.diagnostics()).includes("apple-user-1"), false);
});

test("stores multiple devices with safe diagnostics", () => {
  const registry = new RelayRegistry();
  const record = registry.upsertAppleAccount({ appleSubject: "apple-user-1" });

  const first = registry.upsertDevice({
    userId: record.userId,
    deviceToken: "device-token-one",
    apnsEnvironment: "sandbox",
    appBuild: "100"
  });
  registry.upsertDevice({
    userId: record.userId,
    deviceToken: "device-token-two",
    apnsEnvironment: "production",
    appBuild: "101"
  });

  assert.equal(registry.get(record.userId).deviceToken, "device-token-two");
  assert.equal(registry.diagnostics().users[0].devices.length, 2);
  assert.equal(registry.diagnostics().users[0].devices[0].hasDeviceToken, true);
  assert.equal(JSON.stringify(registry.diagnostics()).includes("device-token-one"), false);

  assert.equal(registry.removeDevice({ userId: record.userId, deviceId: first.id }), true);
  assert.equal(registry.diagnostics().users[0].devices.length, 1);
});

test("disconnects Twitch and deletes account-owned state", () => {
  const registry = new RelayRegistry();
  const record = registry.upsertAppleAccount({ appleSubject: "apple-user-1" });
  registry.setTwitchAuth({
    userId: record.userId,
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
  registry.recordDeliveryAttempt({
    userId: record.userId,
    alert: { correlationId: "proof:1" },
    status: "sent"
  });

  registry.disconnectTwitch(record.userId);
  assert.equal(registry.get(record.userId).twitch, undefined);
  assert.deepEqual(registry.get(record.userId).services, []);

  assert.equal(registry.deleteAccount(record.userId), true);
  assert.equal(registry.get(record.userId), undefined);
  assert.equal(registry.diagnostics().recentDeliveryAttempts.length, 0);
});

test("stores Twitch auth server-side and exposes connector credential", () => {
  const registry = new RelayRegistry();

  const record = registry.setTwitchAuth({
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

  assert.equal(record.twitch.broadcasterId, "1234");
  assert.equal(record.twitch.refreshToken, "refresh-token");
  assert.deepEqual(record.services, ["twitch_native"]);
  assert.deepEqual(record.credentials, [
    {
      service: "twitch_native",
      type: "oauth",
      value: "access-token"
    }
  ]);
});

test("updates stored Twitch access token without dropping refresh token", () => {
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
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  const record = registry.updateTwitchToken({
    userId: "user-1",
    tokenPayload: {
      access_token: "new-access-token",
      expires_in: 7200
    }
  });

  assert.equal(record.twitch.accessToken, "new-access-token");
  assert.equal(record.twitch.refreshToken, "refresh-token");
  assert.deepEqual(record.credentials, [
    {
      service: "twitch_native",
      type: "oauth",
      value: "new-access-token"
    }
  ]);
});

test("finds Twitch records needing refresh by expiry window", () => {
  const registry = new RelayRegistry();
  registry.setTwitchAuth({
    userId: "due-user",
    twitchUser: {
      id: "1234",
      login: "due",
      display_name: "Due"
    },
    tokenPayload: {
      access_token: "due-access-token",
      refresh_token: "due-refresh-token",
      expires_in: 60,
      scope: ["bits:read"]
    },
    scopes: []
  });
  registry.setTwitchAuth({
    userId: "fresh-user",
    twitchUser: {
      id: "5678",
      login: "fresh",
      display_name: "Fresh"
    },
    tokenPayload: {
      access_token: "fresh-access-token",
      refresh_token: "fresh-refresh-token",
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  registry.get("due-user").twitch.expiresAt = "2026-06-16T10:05:00.000Z";
  registry.get("fresh-user").twitch.expiresAt = "2026-06-16T11:00:00.000Z";

  const due = registry.twitchRecordsNeedingRefresh({
    now: new Date("2026-06-16T10:00:00.000Z"),
    refreshWindowMs: 10 * 60 * 1000
  });

  assert.deepEqual(due.map((record) => record.userId), ["due-user"]);
});

test("records Twitch token refresh attempts without raw tokens", () => {
  const registry = new RelayRegistry();
  const attempt = registry.recordTwitchTokenRefreshAttempt({
    userId: "user-1",
    status: "refreshed",
    expiresAt: "2026-06-16T11:00:00.000Z",
    scopes: ["bits:read"],
    now: new Date("2026-06-16T10:00:00.000Z")
  });

  assert.equal(attempt.status, "refreshed");
  assert.equal(attempt.createdAt, "2026-06-16T10:00:00.000Z");
  assert.equal(registry.diagnostics().recentTokenRefreshAttempts[0].userId, "user-1");
  assert.equal(JSON.stringify(registry.diagnostics()).includes("secret-access-token"), false);
});

test("persists provider message dedupe reservations", () => {
  const storePath = tempStorePath();
  const registry = new RelayRegistry({ storage: new LocalJsonStore(storePath) });

  const first = registry.reserveProviderMessage({
    userId: "user-1",
    alert: {
      source: "twitch_native",
      providerMessageId: "msg-1"
    },
    now: new Date("2026-06-16T10:00:00.000Z")
  });

  assert.equal(first.reserved, true);
  assert.equal(first.duplicate, false);

  const reloaded = new RelayRegistry({ storage: new LocalJsonStore(storePath) });
  const duplicate = reloaded.reserveProviderMessage({
    userId: "user-1",
    alert: {
      source: "twitch_native",
      providerMessageId: "msg-1"
    }
  });

  assert.equal(duplicate.reserved, false);
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.firstSeenAt, "2026-06-16T10:00:00.000Z");
  assert.equal(reloaded.diagnostics().providerMessageDedupe.tracked, 1);
});

test("builds a delivery trace across provider receipt, APNs attempt, and app receipt", () => {
  const registry = new RelayRegistry();
  const alert = {
    correlationId: "twitch:message-1",
    providerMessageId: "message-1",
    source: "twitch_native",
    type: "follow"
  };

  registry.reserveProviderMessage({
    userId: "user-1",
    alert,
    now: new Date("2026-06-18T10:00:00.000Z")
  });
  registry.recordDeliveryAttempt({
    userId: "user-1",
    alert,
    status: "queued",
    jobId: "job-1",
    queueAttempt: 0,
    deviceToken: "device-token"
  });
  registry.recordDeliveryAttempt({
    userId: "user-1",
    alert,
    status: "sent",
    result: {
      apnsIds: ["apns-1"],
      summary: { sent: 1, failed: 0 }
    },
    jobId: "job-1",
    queueAttempt: 0,
    deviceToken: "device-token"
  });
  registry.recordAppReceipt({
    userId: "user-1",
    correlationId: "twitch:message-1",
    providerMessageId: "message-1",
    appBuild: "100"
  });

  const trace = registry.deliveryTrace({ correlationId: "twitch:message-1", userId: "user-1" });
  assert.equal(trace.providerMessages.length, 1);
  assert.equal(trace.deliveryAttempts.length, 2);
  assert.equal(trace.appReceipts.length, 1);
  assert.equal(trace.stages.providerReceived, true);
  assert.equal(trace.stages.queued, true);
  assert.equal(trace.stages.apnsAttempted, true);
  assert.equal(trace.stages.apnsSent, true);
  assert.equal(trace.stages.appReceived, true);
});

test("tracks duplicate provider message counts without forwarding duplicates", () => {
  const registry = new RelayRegistry();
  const alert = {
    correlationId: "twitch:message-1",
    providerMessageId: "message-1",
    source: "twitch_native",
    type: "follow"
  };

  const first = registry.reserveProviderMessage({ userId: "user-1", alert });
  const duplicate = registry.reserveProviderMessage({ userId: "user-1", alert });

  assert.equal(first.duplicate, false);
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.duplicateCount, 1);
  assert.equal(registry.diagnostics().providerMessageDedupe.recent[0].duplicateCount, 1);
});

test("persists operational worker heartbeat and proof check summaries", () => {
  const storePath = tempStorePath();
  const registry = new RelayRegistry({ storage: new LocalJsonStore(storePath) });

  registry.recordWorkerHeartbeat({
    workerId: "worker-1",
    processed: true,
    now: new Date("2026-06-18T10:00:00.000Z")
  });
  registry.recordProofCheck({
    status: "passed",
    checks: [
      { name: "database_storage", ok: true, category: "database" },
      { name: "delivery_queue", ok: true, category: "queue" }
    ],
    userId: "user-1",
    correlationId: "proof:one",
    now: new Date("2026-06-18T10:01:00.000Z")
  });

  const reloaded = new RelayRegistry({ storage: new LocalJsonStore(storePath) });
  const diagnostics = reloaded.diagnostics();

  assert.equal(diagnostics.operations.workerHeartbeats["worker-1"].status, "alive");
  assert.equal(diagnostics.operations.workerHeartbeats["worker-1"].processed, true);
  assert.equal(diagnostics.operations.proofChecks[0].status, "passed");
  assert.equal(diagnostics.operations.proofChecks[0].checks[0].category, "database");
  assert.equal(diagnostics.operations.proofChecks[0].correlationId, "proof:one");
});

test("diagnostics omit raw secrets", () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "secret-device-token",
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
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token",
      expires_in: 3600,
      scope: ["bits:read"]
    },
    scopes: []
  });

  const diagnostics = registry.diagnostics();
  const serialized = JSON.stringify(diagnostics);

  assert.equal(diagnostics.users[0].hasDeviceToken, true);
  assert.equal(diagnostics.users[0].deviceTokenLength, "secret-device-token".length);
  assert.equal(diagnostics.users[0].deviceTokenFingerprint.length, 12);
  assert.equal(diagnostics.users[0].twitch.hasAccessToken, true);
  assert.equal(diagnostics.users[0].twitch.hasRefreshToken, true);
  assert.equal(serialized.includes("secret-device-token"), false);
  assert.equal(serialized.includes("secret-access-token"), false);
  assert.equal(serialized.includes("secret-refresh-token"), false);
});

test("records capped delivery attempts for diagnostics", () => {
  const registry = new RelayRegistry();

  const attempt = registry.recordDeliveryAttempt({
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
      summary: { sent: 1, failed: 0, failedReasons: ["BadDeviceToken"] }
    },
    deviceToken: "secret-device-token"
  });

  assert.equal(attempt.correlationId, "twitch:msg-1");
  assert.equal(attempt.providerMessageId, "msg-1");
  assert.equal(attempt.deviceTokenLength, "secret-device-token".length);
  assert.equal(attempt.deviceTokenFingerprint.length, 12);
  assert.equal(attempt.apnsIds[0], "apns-1");
  assert.deepEqual(attempt.apnsFailedReasons, ["BadDeviceToken"]);

  const diagnostics = registry.diagnostics();
  assert.equal(diagnostics.recentDeliveryAttempts[0].status, "sent");
  assert.equal(diagnostics.recentDeliveryAttempts[0].apnsSent, 1);
  assert.equal(JSON.stringify(diagnostics).includes("secret-device-token"), false);

  assert.equal(
    registry.findDeliveryAttempts({ correlationId: "twitch:msg-1" })[0].providerMessageId,
    "msg-1"
  );
  assert.equal(
    registry.findDeliveryAttempts({ providerMessageId: "msg-1", userId: "user-1" }).length,
    1
  );
  assert.equal(
    registry.findDeliveryAttempts({ providerMessageId: "msg-1", userId: "other-user" }).length,
    0
  );
});

test("builds stable device token diagnostics without exposing the token", () => {
  const first = deviceTokenDiagnostics("secret-device-token");
  const second = deviceTokenDiagnostics("secret-device-token");
  const missing = deviceTokenDiagnostics(null);

  assert.equal(first.hasDeviceToken, true);
  assert.equal(first.deviceTokenLength, "secret-device-token".length);
  assert.equal(first.deviceTokenFingerprint, second.deviceTokenFingerprint);
  assert.equal(JSON.stringify(first).includes("secret-device-token"), false);
  assert.equal(missing.hasDeviceToken, false);
  assert.equal(missing.deviceTokenFingerprint, null);
});
