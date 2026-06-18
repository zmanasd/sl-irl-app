import { sendAlertPush } from "./apns.js";
import { RelayConnectorManager } from "./connectors/manager.js";

export async function processDeliveryJob({
  job,
  registry,
  queue = null,
  sendAlert = sendAlertPush,
  logger = console,
  maxAttempts = Number(process.env.RELAY_DELIVERY_MAX_ATTEMPTS ?? 3)
}) {
  const record = registry.get(job.userId);
  if (!record?.deviceToken) {
    const attempt = registry.recordDeliveryAttempt({
      userId: job.userId,
      alert: job.alert,
      status: "failed",
      error: new Error("Registered device token not found."),
      deviceToken: record?.deviceToken ?? null,
      jobId: job.id,
      queueAttempt: job.attempts ?? 0
    });
    await registry.flush?.();
    return { ok: false, attempt, error: "Registered device token not found." };
  }

  try {
    const result = await sendAlert({
      deviceToken: record.deviceToken,
      alert: job.alert
    });
    if (result?.ok !== true && shouldRetryJob(job, maxAttempts)) {
      const retryJob = await enqueueRetry({ queue, job });
      const attempt = registry.recordDeliveryAttempt({
        userId: job.userId,
        alert: job.alert,
        status: "retry_scheduled",
        result,
        deviceToken: record.deviceToken,
        jobId: job.id,
        queueAttempt: job.attempts ?? 0,
        nextRetryAttempt: retryJob?.attempts ?? null
      });
      await registry.flush?.();
      return { ok: false, retryScheduled: true, retryJob, result, attempt };
    }

    const attempt = registry.recordDeliveryAttempt({
      userId: job.userId,
      alert: job.alert,
      status: result?.ok ? "sent" : "failed",
      result,
      deviceToken: record.deviceToken,
      jobId: job.id,
      queueAttempt: job.attempts ?? 0
    });
    await registry.flush?.();
    return { ok: result?.ok === true, result, attempt };
  } catch (error) {
    if (shouldRetryJob(job, maxAttempts)) {
      const retryJob = await enqueueRetry({ queue, job });
      const attempt = registry.recordDeliveryAttempt({
        userId: job.userId,
        alert: job.alert,
        status: "retry_scheduled",
        error,
        deviceToken: record.deviceToken,
        jobId: job.id,
        queueAttempt: job.attempts ?? 0,
        nextRetryAttempt: retryJob?.attempts ?? null
      });
      await registry.flush?.();
      logger.warn?.(
        { userId: job.userId, error: error?.message, retryAttempt: retryJob?.attempts },
        "Queued alert delivery failed; retry scheduled."
      );
      return { ok: false, retryScheduled: true, retryJob, attempt, error: error?.message };
    }

    const attempt = registry.recordDeliveryAttempt({
      userId: job.userId,
      alert: job.alert,
      status: "failed",
      error,
      deviceToken: record.deviceToken,
      jobId: job.id,
      queueAttempt: job.attempts ?? 0
    });
    await registry.flush?.();
    logger.error?.({ userId: job.userId, error: error?.message }, "Queued alert delivery failed.");
    return { ok: false, attempt, error: error?.message };
  }
}

export async function processOneDeliveryJob({
  queue,
  registry,
  sendAlert = sendAlertPush,
  logger = console,
  timeoutMs = 0,
  maxAttempts = Number(process.env.RELAY_DELIVERY_MAX_ATTEMPTS ?? 3)
}) {
  const job = await queue.next({ timeoutMs });
  if (!job) return { ok: true, processed: false };

  const result = await processDeliveryJob({
    job,
    queue,
    registry,
    sendAlert,
    logger,
    maxAttempts
  });
  return {
    ...result,
    processed: true,
    jobId: job.id
  };
}

export async function runDeliveryWorker({
  queue,
  registry,
  logger = console,
  sendAlert = sendAlertPush,
  pollTimeoutMs = 5000,
  heartbeatIntervalMs = Number(process.env.RELAY_WORKER_HEARTBEAT_INTERVAL_MS ?? 30000),
  workerId = process.env.RELAY_WORKER_ID ?? "default",
  shouldStop = () => false
}) {
  let lastHeartbeatAt = 0;
  while (!shouldStop()) {
    const result = await processOneDeliveryJob({
      queue,
      registry,
      sendAlert,
      logger,
      timeoutMs: pollTimeoutMs
    });
    const now = Date.now();
    if (heartbeatIntervalMs > 0 && now - lastHeartbeatAt >= heartbeatIntervalMs) {
      try {
        registry.recordWorkerHeartbeat({
          workerId,
          status: "alive",
          processed: result.processed === true
        });
        await registry.flush?.();
        lastHeartbeatAt = now;
      } catch (error) {
        logger.warn?.({ error: error?.message }, "Failed to record relay worker heartbeat.");
      }
    }
  }
}

export function createWorkerConnectorManager({
  registry,
  queue,
  logger
}) {
  return new RelayConnectorManager({
    registry,
    logger,
    sendAlert: async ({ deviceToken, alert, userId = null }) => {
      const targetUserId = userId ?? findUserIdByDeviceToken(registry, deviceToken);
      if (!targetUserId) {
        return {
          ok: false,
          error: "QUEUE_USER_NOT_FOUND",
          summary: { sent: 0, failed: 1, failedReasons: ["QUEUE_USER_NOT_FOUND"] }
        };
      }
      const job = await queue.enqueue({ userId: targetUserId, alert });
      return {
        ok: true,
        queued: true,
        jobId: job.id,
        summary: { sent: 0, failed: 0 }
      };
    }
  });
}

function findUserIdByDeviceToken(registry, deviceToken) {
  for (const userId of registry.userIds()) {
    if (registry.get(userId)?.deviceToken === deviceToken) {
      return userId;
    }
  }
  return null;
}

function shouldRetryJob(job, maxAttempts) {
  if (!job || !maxAttempts || maxAttempts <= 1) return false;
  return Number(job.attempts ?? 0) + 1 < maxAttempts;
}

async function enqueueRetry({ queue, job }) {
  if (!queue) return null;
  return queue.enqueue({
    ...job,
    attempts: Number(job.attempts ?? 0) + 1,
    retryOfJobId: job.id,
    createdAt: new Date().toISOString()
  });
}
