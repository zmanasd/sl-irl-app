import { createDefaultRegistryAsync, createLogger, createRelayApp } from "./app.js";
import { createDeliveryQueueFromEnv } from "./queue.js";
import { initSentry } from "./observability.js";
import { createWorkerConnectorManager, runDeliveryWorker } from "./worker.js";

const logger = createLogger();
await initSentry({ env: process.env, logger });
const registry = await createDefaultRegistryAsync(process.env);
const queue = await createDeliveryQueueFromEnv(process.env);
const connectorManager = createWorkerConnectorManager({
  registry,
  queue,
  logger
});

const { refreshDueTwitchTokens, syncAllUsers } = createRelayApp({
  registry,
  logger,
  deliveryQueue: queue,
  connectorManager
});

async function runStartupRecovery() {
  try {
    const refreshResults = await refreshDueTwitchTokens();
    const refreshed = refreshResults.filter((result) => result.ok).length;
    const refreshFailed = refreshResults.length - refreshed;
    if (refreshResults.length > 0) {
      logger.info({ refreshed, failed: refreshFailed }, "Worker completed startup Twitch token refresh pass.");
    }

    const syncResults = await syncAllUsers();
    const synced = syncResults.filter((result) => result.ok).length;
    const syncFailed = syncResults.length - synced;
    logger.info({ synced, failed: syncFailed }, "Worker completed startup connector recovery pass.");
  } catch (error) {
    logger.error({ error: error.message }, "Worker startup recovery failed.");
  }
}

await runStartupRecovery();

const refreshIntervalSeconds = Number(process.env.TWITCH_TOKEN_REFRESH_INTERVAL_SECONDS ?? 300);
if (refreshIntervalSeconds > 0) {
  setInterval(async () => {
    try {
      const results = await refreshDueTwitchTokens();
      const refreshed = results.filter((result) => result.ok).length;
      const failed = results.length - refreshed;
      if (results.length > 0) {
        logger.info({ refreshed, failed }, "Worker completed scheduled Twitch token refresh pass.");
      }
    } catch (error) {
      logger.error({ error: error.message }, "Worker scheduled Twitch token refresh failed.");
    }
  }, refreshIntervalSeconds * 1000).unref();
}

logger.info("Relay worker started.");
await runDeliveryWorker({
  queue,
  registry,
  logger,
  pollTimeoutMs: Number(process.env.RELAY_WORKER_POLL_TIMEOUT_MS ?? 5000)
});
