import WebSocket from "ws";
import crypto from "crypto";

const TWITCH_WS_URL = "wss://eventsub.wss.twitch.tv/ws";
const HELIX_BASE_URL = "https://api.twitch.tv/helix";

const SUBSCRIPTIONS = [
  {
    type: "channel.follow",
    version: "2",
    buildCondition: (userId) => ({
      broadcaster_user_id: userId,
      moderator_user_id: userId
    })
  },
  {
    type: "channel.subscribe",
    version: "1",
    buildCondition: (userId) => ({
      broadcaster_user_id: userId
    })
  },
  {
    type: "channel.cheer",
    version: "1",
    buildCondition: (userId) => ({
      broadcaster_user_id: userId
    })
  },
  {
    type: "channel.raid",
    version: "1",
    buildCondition: (userId) => ({
      to_broadcaster_user_id: userId
    })
  }
];

export class TwitchEventSubConnector {
  constructor({ userId, token, clientId, onAlert, logger }) {
    this.userId = userId;
    this.token = token;
    this.clientId = clientId;
    this.onAlert = onAlert;
    this.logger = logger;
    this.socket = null;
    this.sessionId = null;
    this.broadcasterId = null;
    this.lastMessageIds = new Set();
    this.reconnectUrl = null;
    this.isStopped = false;
  }

  async start() {
    if (this.socket || this.isStopped) return;
    if (!this.clientId) {
      this.logger.error({ userId: this.userId }, "Missing TWITCH_CLIENT_ID; cannot connect.");
      return;
    }

    try {
      this.broadcasterId = await this.fetchUserId();
    } catch (error) {
      this.logger.error({ userId: this.userId, error: error?.message }, "Failed to fetch Twitch user ID.");
      return;
    }

    this.connectWebSocket(TWITCH_WS_URL);
  }

  stop() {
    this.isStopped = true;
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }

  connectWebSocket(url) {
    if (this.isStopped) return;
    this.socket = new WebSocket(url);

    this.socket.on("open", () => {
      this.logger.info({ userId: this.userId }, "Twitch EventSub socket connected.");
    });

    this.socket.on("close", () => {
      this.logger.warn({ userId: this.userId }, "Twitch EventSub socket disconnected.");
      this.socket = null;
      this.sessionId = null;
      if (!this.isStopped) {
        setTimeout(() => this.connectWebSocket(this.reconnectUrl ?? TWITCH_WS_URL), 2000);
      }
    });

    this.socket.on("error", (error) => {
      this.logger.error({ userId: this.userId, error: error?.message }, "Twitch EventSub socket error.");
    });

    this.socket.on("message", (data) => {
      this.handleMessage(data);
    });
  }

  async handleMessage(raw) {
    let payload = null;
    try {
      payload = JSON.parse(raw.toString());
    } catch {
      return;
    }

    const metadata = payload?.metadata ?? {};
    const messageType = metadata.message_type;
    const messageId = metadata.message_id;

    if (messageId && this.lastMessageIds.has(messageId)) {
      return;
    }

    if (messageId) {
      this.lastMessageIds.add(messageId);
      if (this.lastMessageIds.size > 200) {
        this.lastMessageIds = new Set(Array.from(this.lastMessageIds).slice(-100));
      }
    }

    switch (messageType) {
      case "session_welcome":
        this.sessionId = payload?.payload?.session?.id ?? null;
        this.reconnectUrl = payload?.payload?.session?.reconnect_url ?? null;
        if (this.sessionId) {
          await this.subscribeAll();
        }
        break;
      case "session_reconnect": {
        const reconnectUrl = payload?.payload?.session?.reconnect_url;
        if (reconnectUrl) {
          this.reconnectUrl = reconnectUrl;
          this.socket?.close();
        }
        break;
      }
      case "notification":
        this.handleNotification(metadata, payload?.payload?.event);
        break;
      case "revocation":
        this.logger.warn({ userId: this.userId }, "Twitch subscription revoked.");
        break;
      default:
        break;
    }
  }

  async subscribeAll() {
    if (!this.sessionId || !this.broadcasterId) return;

    for (const sub of SUBSCRIPTIONS) {
      await this.createSubscription({
        type: sub.type,
        version: sub.version,
        condition: sub.buildCondition(this.broadcasterId),
        sessionId: this.sessionId
      });
    }
  }

  async createSubscription({ type, version, condition, sessionId }) {
    const url = `${HELIX_BASE_URL}/eventsub/subscriptions`;
    const payload = {
      type,
      version,
      condition,
      transport: {
        method: "websocket",
        session_id: sessionId
      }
    };

    try {
      const response = await this.fetch(url, {
        method: "POST",
        headers: {
          "Client-Id": this.clientId,
          "Authorization": `Bearer ${this.token}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        const text = await response.text();
        this.logger.warn({ userId: this.userId, type, status: response.status, text }, "Failed to create Twitch subscription.");
      }
    } catch (error) {
      this.logger.error({ userId: this.userId, error: error?.message }, "Error creating Twitch subscription.");
    }
  }

  async fetchUserId() {
    const url = `${HELIX_BASE_URL}/users`;
    const response = await this.fetch(url, {
      headers: {
        "Client-Id": this.clientId,
        "Authorization": `Bearer ${this.token}`
      }
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`Failed to fetch user: ${response.status} ${text}`);
    }

    const payload = await response.json();
    const user = payload?.data?.[0];
    if (!user?.id) {
      throw new Error("Twitch user not found for token.");
    }

    return user.id;
  }

  handleNotification(metadata, event) {
    if (!event || typeof event !== "object") return;
    const type = metadata?.subscription_type;
    let alert = null;

    if (type === "channel.follow") {
      alert = {
        alert_id: metadata.message_id ?? crypto.randomUUID(),
        type: "follow",
        username: event.user_name ?? event.user_login ?? "Unknown",
        message: null,
        amount: null,
        formatted_amount: null,
        sound_url: null,
        timestamp: event.followed_at ?? new Date().toISOString(),
        source: "twitch_native"
      };
    } else if (type === "channel.subscribe") {
      alert = {
        alert_id: metadata.message_id ?? crypto.randomUUID(),
        type: "subscription",
        username: event.user_name ?? event.user_login ?? "Unknown",
        message: null,
        amount: null,
        formatted_amount: null,
        sound_url: null,
        timestamp: new Date().toISOString(),
        source: "twitch_native"
      };
    } else if (type === "channel.cheer") {
      const bits = Number(event.bits ?? 0);
      alert = {
        alert_id: metadata.message_id ?? crypto.randomUUID(),
        type: "bits",
        username: event.user_name ?? event.user_login ?? "Anonymous",
        message: event.message ?? null,
        amount: Number.isNaN(bits) ? null : bits,
        formatted_amount: null,
        sound_url: null,
        timestamp: new Date().toISOString(),
        source: "twitch_native"
      };
    } else if (type === "channel.raid") {
      alert = {
        alert_id: metadata.message_id ?? crypto.randomUUID(),
        type: "raid",
        username: event.from_broadcaster_user_name ?? event.from_broadcaster_user_login ?? "Unknown",
        message: null,
        amount: event.viewers ?? null,
        formatted_amount: null,
        sound_url: null,
        timestamp: new Date().toISOString(),
        source: "twitch_native"
      };
    }

    if (alert) {
      this.onAlert(alert);
    }
  }

  async fetch(url, options) {
    if (typeof globalThis.fetch === "function") {
      return globalThis.fetch(url, options);
    }

    const { default: fetchImpl } = await import("node-fetch");
    return fetchImpl(url, options);
  }
}
