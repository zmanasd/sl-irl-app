import WebSocket from "ws";
import crypto from "crypto";

const SUPPORTED_TYPES = new Set([
  "tip",
  "follow",
  "subscriber",
  "raid",
  "host",
  "cheer"
]);

export class StreamElementsConnector {
  constructor({ userId, token, tokenType, onAlert, logger }) {
    this.userId = userId;
    this.token = token;
    this.tokenType = tokenType;
    this.onAlert = onAlert;
    this.logger = logger;
    this.socket = null;
  }

  start() {
    if (this.socket) return;

    this.socket = new WebSocket("wss://astro.streamelements.com");

    this.socket.on("open", () => {
      this.logger.info({ userId: this.userId }, "StreamElements socket connected.");
      this.sendSubscribe();
    });

    this.socket.on("close", () => {
      this.logger.warn({ userId: this.userId }, "StreamElements socket disconnected.");
    });

    this.socket.on("error", (error) => {
      this.logger.error({ userId: this.userId, error: error?.message }, "StreamElements socket error.");
    });

    this.socket.on("message", (data) => {
      this.handleMessage(data);
    });
  }

  stop() {
    if (!this.socket) return;
    this.socket.close();
    this.socket = null;
  }

  sendSubscribe() {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;

    const message = {
      type: "subscribe",
      nonce: crypto.randomUUID(),
      data: {
        topic: "channel.activities",
        token: this.token,
        token_type: this.tokenType
      }
    };

    this.socket.send(JSON.stringify(message));
  }

  handleMessage(raw) {
    let payload = null;
    try {
      payload = JSON.parse(raw.toString());
    } catch {
      return;
    }

    if (!payload || payload.type !== "message") return;
    if (payload.topic !== "channel.activities") return;

    const data = payload.data ?? {};
    const type = (data.type ?? "").toString().toLowerCase();
    if (!SUPPORTED_TYPES.has(type)) return;

    const details = data.data ?? {};
    const username = details.username ?? details.displayName ?? "Unknown";
    const message = details.message ?? null;

    let amount = null;
    if (typeof details.amount === "number") amount = details.amount;
    if (typeof details.amount === "string") amount = Number(details.amount);
    if (Number.isNaN(amount)) amount = null;

    let mappedType = type;
    if (type === "tip") mappedType = "donation";
    if (type === "subscriber") mappedType = "subscription";
    if (type === "cheer") mappedType = "bits";

    let formattedAmount = null;
    if (typeof details.amountFormatted === "string") {
      formattedAmount = details.amountFormatted;
    } else if (typeof details.amountFormatted === "number") {
      formattedAmount = details.amountFormatted.toString();
    }

    const alert = {
      alert_id: details._id ?? crypto.randomUUID(),
      type: mappedType,
      username,
      message,
      amount,
      formatted_amount: formattedAmount,
      sound_url: details.sound ?? null,
      timestamp: new Date().toISOString(),
      source: "stream_elements"
    };

    this.onAlert(alert);
  }
}
