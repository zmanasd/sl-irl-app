import test from "node:test";
import assert from "node:assert/strict";
import { RelayConnectorManager } from "../src/connectors/manager.js";
import { RelayRegistry } from "../src/registry.js";

const logger = {
  info() {},
  warn() {},
  error() {}
};

test("records sent delivery attempts from connector alerts", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });

  const manager = new RelayConnectorManager({
    registry,
    logger,
    sendAlert: async () => ({
      ok: true,
      apnsIds: ["apns-1"],
      summary: { sent: 1, failed: 0 }
    })
  });

  await manager.handleAlert("user-1", {
    correlationId: "twitch:msg-1",
    providerMessageId: "msg-1",
    source: "twitch_native",
    type: "follow"
  });

  const [attempt] = registry.diagnostics().recentDeliveryAttempts;
  assert.equal(attempt.status, "sent");
  assert.equal(attempt.correlationId, "twitch:msg-1");
  assert.equal(attempt.apnsIds[0], "apns-1");
  assert.equal(attempt.deviceTokenFingerprint.length, 12);
  assert.equal(attempt.deviceTokenLength, "device-token".length);
});

test("skips duplicate provider messages across connector alerts", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });

  let sendCount = 0;
  const manager = new RelayConnectorManager({
    registry,
    logger,
    sendAlert: async () => {
      sendCount += 1;
      return {
        ok: true,
        apnsIds: [`apns-${sendCount}`],
        summary: { sent: 1, failed: 0 }
      };
    }
  });

  const alert = {
    correlationId: "twitch:msg-1",
    providerMessageId: "msg-1",
    source: "twitch_native",
    type: "follow"
  };

  await manager.handleAlert("user-1", alert);
  await manager.handleAlert("user-1", alert);

  const attempts = registry.diagnostics().recentDeliveryAttempts;
  assert.equal(sendCount, 1);
  assert.equal(attempts[0].status, "sent");
  assert.equal(attempts[1].status, "duplicate_provider_message");
  assert.equal(registry.diagnostics().providerMessageDedupe.tracked, 1);
});

test("syncs all persisted users for restart recovery", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token-1",
    services: ["twitch_native"],
    credentials: []
  });
  registry.register({
    userId: "user-2",
    deviceToken: "device-token-2",
    services: ["twitch_native"],
    credentials: []
  });

  const manager = new RelayConnectorManager({
    registry,
    logger,
    sendAlert: async () => ({ ok: true })
  });
  const synced = [];
  manager.syncForUser = async (userId) => {
    synced.push(userId);
  };

  const results = await manager.syncAllUsers();
  const diagnostics = manager.recoveryDiagnostics();

  assert.deepEqual(synced, ["user-1", "user-2"]);
  assert.deepEqual(results, [
    { userId: "user-1", ok: true },
    { userId: "user-2", ok: true }
  ]);
  assert.equal(diagnostics.syncedUsers, 2);
  assert.equal(diagnostics.failedUsers, 0);
  assert.equal(typeof diagnostics.lastSyncAllAt, "string");
});

test("aggregates connector diagnostics", () => {
  const registry = new RelayRegistry();
  const manager = new RelayConnectorManager({
    registry,
    logger,
    sendAlert: async () => ({ ok: true })
  });

  manager.connectors.set("user-1:twitch_native", {
    diagnostics: () => ({
      service: "twitch_native",
      status: "session_ready"
    })
  });

  assert.deepEqual(manager.diagnostics(), [
    {
      key: "user-1:twitch_native",
      service: "twitch_native",
      status: "session_ready"
    }
  ]);
});
