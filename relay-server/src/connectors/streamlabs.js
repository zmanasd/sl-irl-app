import { io } from "socket.io-client";
import crypto from "crypto";

const SUPPORTED_TYPES = new Set([
  "donation",
  "follow",
  "subscription",
  "host",
  "raid",
  "bits",
  "subgift",
  "submysterygift"
]);

export class StreamlabsConnector {
  constructor({ userId, token, onAlert, logger }) {
    this.userId = userId;
    this.token = token;
    this.onAlert = onAlert;
    this.logger = logger;
    this.socket = null;
  }

  start() {
    if (this.socket) return;

    this.socket = io("https://sockets.streamlabs.com", {
      transports: ["websocket"],
      query: { token: this.token },
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 30000
    });

    this.socket.on("connect", () => {
      this.logger.info({ userId: this.userId }, "Streamlabs socket connected.");
    });

    this.socket.on("disconnect", () => {
      this.logger.warn({ userId: this.userId }, "Streamlabs socket disconnected.");
    });

    this.socket.on("connect_error", (error) => {
      this.logger.error({ userId: this.userId, error: error?.message }, "Streamlabs socket error.");
    });

    this.socket.on("event", (payload) => {
      this.handleEvent(payload);
    });
  }

  stop() {
    if (!this.socket) return;
    this.socket.removeAllListeners();
    this.socket.disconnect();
    this.socket = null;
  }

  handleEvent(payload) {
    if (!payload || typeof payload !== "object") return;

    const type = (payload.type ?? "").toString().toLowerCase();
    if (!SUPPORTED_TYPES.has(type)) return;

    const messages = Array.isArray(payload.message) ? payload.message : [];
    for (const message of messages) {
      const alert = this.parseMessage(type, message);
      if (alert) {
        this.onAlert(alert);
      }
    }
  }

  parseMessage(type, message) {
    if (!message || typeof message !== "object") return null;

    const username = message.name ?? "Unknown";
    const soundUrl = message.sound_url ?? null;

    let amount = null;
    if (typeof message.amount === "number") amount = message.amount;
    if (typeof message.amount === "string") amount = Number(message.amount);
    if (Number.isNaN(amount)) amount = null;

    let mappedType = type;
    if (type === "subgift" || type === "submysterygift") {
      mappedType = "subscription";
    }

    return {
      alert_id: message.id ?? crypto.randomUUID(),
      type: mappedType,
      username,
      message: message.message ?? null,
      amount,
      formatted_amount: message.formatted_amount ?? null,
      sound_url: soundUrl,
      timestamp: new Date().toISOString(),
      source: "streamlabs"
    };
  }
}
