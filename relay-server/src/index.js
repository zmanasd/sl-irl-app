import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import pino from "pino";
import { RelayRegistry } from "./registry.js";
import { sendAlertPush } from "./apns.js";
import { RelayConnectorManager } from "./connectors/manager.js";

const logger = pino({
  transport: {
    target: "pino-pretty",
    options: { colorize: true }
  }
});

const app = express();
app.use(express.json({ limit: "1mb" }));

const registry = new RelayRegistry();
const connectorManager = new RelayConnectorManager({
  registry,
  logger,
  sendAlert: sendAlertPush
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, users: registry.count() });
});

app.post("/register", (req, res) => {
  const { userId, deviceToken, services, credentials } = req.body ?? {};
  if (!userId || !deviceToken) {
    return res.status(400).json({ error: "userId and deviceToken are required." });
  }

  registry.register({
    userId,
    deviceToken,
    services: Array.isArray(services) ? services : [],
    credentials: Array.isArray(credentials) ? credentials : []
  });

  connectorManager.syncForUser(userId);
  logger.info({ userId }, "User registered for relay.");
  return res.json({ ok: true });
});

app.post("/presence", (req, res) => {
  const { userId, deviceToken, directConnectionActive } = req.body ?? {};
  if (!userId || typeof directConnectionActive !== "boolean") {
    return res.status(400).json({ error: "userId and directConnectionActive are required." });
  }

  registry.setPresence({ userId, directConnectionActive });
  registry.updateDeviceToken({ userId, deviceToken });
  connectorManager.syncForUser(userId);
  logger.info({ userId, directConnectionActive }, "Updated presence.");
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

  if (record.directConnectionActive) {
    return res.status(409).json({ error: "direct connection active" });
  }

  const result = await sendAlertPush({
    deviceToken: record.deviceToken,
    alert
  });

  return res.json({ ok: true, result });
});

app.post("/soundalerts/webhook", async (req, res) => {
  const { userId, alert } = req.body ?? {};
  if (!userId || !alert) {
    return res.status(400).json({ error: "userId and alert are required." });
  }

  const record = registry.get(userId);
  if (!record) {
    return res.status(404).json({ error: "user not registered" });
  }

  if (record.directConnectionActive) {
    return res.status(409).json({ error: "direct connection active" });
  }

  const result = await sendAlertPush({
    deviceToken: record.deviceToken,
    alert
  });

  return res.json({ ok: true, result });
});

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
