import test from "node:test";
import assert from "node:assert/strict";
import { RelayRegistry } from "../src/registry.js";
import { MemoryDeliveryQueue } from "../src/queue.js";
import { processOneDeliveryJob, runDeliveryWorker } from "../src/worker.js";

const logger = {
  info() {},
  warn() {},
  error() {}
};

test("memory delivery queue processes APNs jobs with correlation evidence", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });
  const queue = new MemoryDeliveryQueue();
  const alert = {
    correlationId: "proof:job-1",
    providerMessageId: "proof-job-1",
    source: "twitch_native",
    type: "follow"
  };

  const job = await queue.enqueue({ userId: "user-1", alert });
  assert.equal(job.id.startsWith("job_"), true);
  assert.equal(await queue.length(), 1);

  const result = await processOneDeliveryJob({
    queue,
    registry,
    logger,
    sendAlert: async ({ deviceToken, alert: sentAlert }) => {
      assert.equal(deviceToken, "device-token");
      assert.equal(sentAlert.correlationId, "proof:job-1");
      return {
        ok: true,
        apnsIds: ["apns-1"],
        summary: { sent: 1, failed: 0 }
      };
    }
  });

  assert.equal(result.processed, true);
  assert.equal(result.ok, true);
  assert.equal(await queue.length(), 0);
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].status, "sent");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].correlationId, "proof:job-1");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].apnsIds[0], "apns-1");
});

test("queued delivery records a categorized failure when the device is missing", async () => {
  const registry = new RelayRegistry();
  const queue = new MemoryDeliveryQueue();
  await queue.enqueue({
    userId: "missing-user",
    alert: {
      correlationId: "proof:missing-device",
      source: "twitch_native"
    }
  });

  const result = await processOneDeliveryJob({
    queue,
    registry,
    logger
  });

  assert.equal(result.processed, true);
  assert.equal(result.ok, false);
  assert.equal(result.error, "Registered device token not found.");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].status, "failed");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].error, "Registered device token not found.");
});

test("queued delivery schedules bounded retries for failed APNs sends", async () => {
  const registry = new RelayRegistry();
  registry.register({
    userId: "user-1",
    deviceToken: "device-token",
    services: ["twitch_native"],
    credentials: []
  });
  const queue = new MemoryDeliveryQueue();
  await queue.enqueue({
    userId: "user-1",
    alert: {
      correlationId: "proof:retry",
      providerMessageId: "proof-retry",
      source: "twitch_native"
    }
  });

  const first = await processOneDeliveryJob({
    queue,
    registry,
    logger,
    maxAttempts: 2,
    sendAlert: async () => ({
      ok: false,
      error: "APNS_TEMPORARY_FAILURE",
      summary: { sent: 0, failed: 1, failedReasons: ["TooManyRequests"] }
    })
  });

  assert.equal(first.processed, true);
  assert.equal(first.retryScheduled, true);
  assert.equal(await queue.length(), 1);
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].status, "retry_scheduled");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].queueAttempt, 0);
  assert.equal(registry.diagnostics().recentDeliveryAttempts[0].nextRetryAttempt, 1);

  const second = await processOneDeliveryJob({
    queue,
    registry,
    logger,
    maxAttempts: 2,
    sendAlert: async () => ({
      ok: false,
      error: "APNS_TEMPORARY_FAILURE",
      summary: { sent: 0, failed: 1, failedReasons: ["TooManyRequests"] }
    })
  });

  assert.equal(second.processed, true);
  assert.equal(second.retryScheduled, undefined);
  assert.equal(await queue.length(), 0);
  assert.equal(registry.diagnostics().recentDeliveryAttempts[1].status, "failed");
  assert.equal(registry.diagnostics().recentDeliveryAttempts[1].queueAttempt, 1);
});

test("delivery worker records shared heartbeat evidence", async () => {
  const registry = new RelayRegistry();
  const queue = new MemoryDeliveryQueue();
  let shouldStopCalls = 0;

  await runDeliveryWorker({
    queue,
    registry,
    logger,
    pollTimeoutMs: 0,
    heartbeatIntervalMs: 1,
    workerId: "test-worker",
    shouldStop: () => shouldStopCalls++ > 0
  });

  const heartbeat = registry.diagnostics().operations.workerHeartbeats["test-worker"];
  assert.equal(heartbeat.workerId, "test-worker");
  assert.equal(heartbeat.status, "alive");
  assert.equal(heartbeat.processed, false);
});
