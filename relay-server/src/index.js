import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import pino from "pino";
import { RelayRegistry } from "./registry.js";

const logger = pino({
  transport: {
    target: "pino-pretty",
    options: { colorize: true }
  }
});

const app = express();
app.use(express.json({ limit: "1mb" }));

const registry = new RelayRegistry();

app.get("/health", (_req, res) => {
  res.json({ ok: true, users: registry.count() });
});

app.post("/register", (req, res) => {
  const { userId, deviceToken, services } = req.body ?? {};
  if (!userId || !deviceToken) {
    return res.status(400).json({ error: "userId and deviceToken are required." });
  }

  registry.register({
    userId,
    deviceToken,
    services: Array.isArray(services) ? services : []
  });

  logger.info({ userId }, "User registered for relay.");
  return res.json({ ok: true });
});

app.post("/presence", (req, res) => {
  const { userId, directConnectionActive } = req.body ?? {};
  if (!userId || typeof directConnectionActive !== "boolean") {
    return res.status(400).json({ error: "userId and directConnectionActive are required." });
  }

  registry.setPresence({ userId, directConnectionActive });
  logger.info({ userId, directConnectionActive }, "Updated presence.");
  return res.json({ ok: true });
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
