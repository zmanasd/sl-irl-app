import { createServer } from "http";
import { WebSocketServer } from "ws";
import { createLogger, createRelayApp } from "./app.js";

const logger = createLogger();
const { app, refreshDueTwitchTokens, syncAllUsers } = createRelayApp({ logger });

const server = createServer(app);
const wss = new WebSocketServer({ server });

wss.on("connection", (socket) => {
  logger.info("Admin socket connected.");
  socket.send(JSON.stringify({ message: "Relay server online." }));
});

const port = Number(process.env.PORT ?? 3000);
server.listen(port, () => {
  logger.info(`Relay server listening on :${port}`);
});

async function runStartupRecovery() {
  try {
    const refreshResults = await refreshDueTwitchTokens();
    const refreshed = refreshResults.filter((result) => result.ok).length;
    const refreshFailed = refreshResults.length - refreshed;
    if (refreshResults.length > 0) {
      logger.info({ refreshed, failed: refreshFailed }, "Completed startup Twitch token refresh pass.");
    }

    const syncResults = await syncAllUsers();
    const synced = syncResults.filter((result) => result.ok).length;
    const syncFailed = syncResults.length - synced;
    logger.info({ synced, failed: syncFailed }, "Completed startup connector recovery pass.");
  } catch (error) {
    logger.error({ error: error.message }, "Startup relay recovery failed.");
  }
}

runStartupRecovery();

const refreshIntervalSeconds = Number(process.env.TWITCH_TOKEN_REFRESH_INTERVAL_SECONDS ?? 300);
if (refreshIntervalSeconds > 0) {
  setInterval(async () => {
    try {
      const results = await refreshDueTwitchTokens();
      const refreshed = results.filter((result) => result.ok).length;
      const failed = results.length - refreshed;
      if (results.length > 0) {
        logger.info({ refreshed, failed }, "Completed scheduled Twitch token refresh pass.");
      }
    } catch (error) {
      logger.error({ error: error.message }, "Scheduled Twitch token refresh pass failed.");
    }
  }, refreshIntervalSeconds * 1000).unref();
}
