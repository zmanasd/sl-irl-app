import { normalizeTwitchNotification } from "./twitch-normalizer.js";
import { TWITCH_EVENTSUB_SUBSCRIPTIONS } from "./twitch-subscriptions.js";

const TWITCH_WS_URL = "wss://eventsub.wss.twitch.tv/ws";
const HELIX_BASE_URL = "https://api.twitch.tv/helix";
const KEEPALIVE_GRACE_MULTIPLIER = 2;

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
    this.status = "idle";
    this.connectionAttempts = 0;
    this.reconnectCount = 0;
    this.lastConnectedAt = null;
    this.lastDisconnectedAt = null;
    this.lastKeepaliveAt = null;
    this.keepaliveTimeoutSeconds = null;
    this.lastError = null;
    this.lastNotificationAt = null;
    this.lastRevocationAt = null;
    this.subscriptionResults = new Map();
  }

  async start() {
    if (this.socket || this.isStopped) return;
    if (!this.clientId) {
      this.status = "error";
      this.lastError = "Missing TWITCH_CLIENT_ID";
      this.logger.error({ userId: this.userId }, "Missing TWITCH_CLIENT_ID; cannot connect.");
      return;
    }

    this.status = "fetching_user";
    try {
      this.broadcasterId = await this.fetchUserId();
    } catch (error) {
      this.status = "error";
      this.lastError = error?.message ?? "Failed to fetch Twitch user ID.";
      this.logger.error({ userId: this.userId, error: error?.message }, "Failed to fetch Twitch user ID.");
      return;
    }

    await this.connectWebSocket(TWITCH_WS_URL);
  }

  stop() {
    this.isStopped = true;
    this.status = "stopped";
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }

  async connectWebSocket(url) {
    if (this.isStopped) return;
    this.status = "connecting";
    this.connectionAttempts += 1;
    const { default: WebSocket } = await import("ws");
    this.socket = new WebSocket(url);

    this.socket.on("open", () => {
      this.status = "connected";
      this.lastConnectedAt = new Date().toISOString();
      this.lastError = null;
      this.logger.info({ userId: this.userId }, "Twitch EventSub socket connected.");
    });

    this.socket.on("close", () => {
      this.logger.warn({ userId: this.userId }, "Twitch EventSub socket disconnected.");
      this.socket = null;
      this.sessionId = null;
      this.lastDisconnectedAt = new Date().toISOString();
      if (!this.isStopped) {
        this.status = "reconnecting";
        this.reconnectCount += 1;
        setTimeout(() => this.connectWebSocket(this.reconnectUrl ?? TWITCH_WS_URL), 2000);
      }
    });

    this.socket.on("error", (error) => {
      this.status = "error";
      this.lastError = error?.message ?? "Twitch EventSub socket error.";
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
        this.status = "session_ready";
        this.lastKeepaliveAt = new Date().toISOString();
        this.keepaliveTimeoutSeconds = payload?.payload?.session?.keepalive_timeout_seconds ?? null;
        if (this.sessionId) {
          await this.subscribeAll();
        }
        break;
      case "session_keepalive":
        this.lastKeepaliveAt = new Date().toISOString();
        this.keepaliveTimeoutSeconds = payload?.payload?.session?.keepalive_timeout_seconds
          ?? this.keepaliveTimeoutSeconds;
        break;
      case "session_reconnect": {
        const reconnectUrl = payload?.payload?.session?.reconnect_url;
        if (reconnectUrl) {
          this.reconnectUrl = reconnectUrl;
          this.status = "reconnect_requested";
          this.reconnectCount += 1;
          this.socket?.close();
        }
        break;
      }
      case "notification":
        this.lastNotificationAt = new Date().toISOString();
        this.handleNotification(metadata, payload?.payload?.event);
        break;
      case "revocation":
        this.lastRevocationAt = new Date().toISOString();
        this.logger.warn({ userId: this.userId }, "Twitch subscription revoked.");
        break;
      default:
        break;
    }
  }

  async subscribeAll() {
    if (!this.sessionId || !this.broadcasterId) return;

    for (const sub of TWITCH_EVENTSUB_SUBSCRIPTIONS) {
      if (sub.optionalForMvp) continue;
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
        this.subscriptionResults.set(type, {
          type,
          ok: false,
          status: response.status,
          error: text,
          updatedAt: new Date().toISOString()
        });
        this.logger.warn({ userId: this.userId, type, status: response.status, text }, "Failed to create Twitch subscription.");
        return;
      }

      const result = await response.json().catch(() => null);
      this.subscriptionResults.set(type, {
        type,
        ok: true,
        status: response.status,
        subscriptionId: result?.data?.[0]?.id ?? null,
        updatedAt: new Date().toISOString()
      });
    } catch (error) {
      this.subscriptionResults.set(type, {
        type,
        ok: false,
        status: null,
        error: error?.message ?? "Error creating Twitch subscription.",
        updatedAt: new Date().toISOString()
      });
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
    const alert = normalizeTwitchNotification(metadata, event);
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

  isKeepaliveStale(now = new Date()) {
    if (!this.lastKeepaliveAt || !this.keepaliveTimeoutSeconds) return false;
    const last = Date.parse(this.lastKeepaliveAt);
    if (Number.isNaN(last)) return false;
    const maxAgeMs = this.keepaliveTimeoutSeconds * KEEPALIVE_GRACE_MULTIPLIER * 1000;
    return now.getTime() - last > maxAgeMs;
  }

  diagnostics(now = new Date()) {
    return {
      service: "twitch_native",
      userId: this.userId,
      status: this.status,
      hasSocket: Boolean(this.socket),
      isStopped: this.isStopped,
      broadcasterId: this.broadcasterId,
      sessionId: this.sessionId,
      hasReconnectUrl: Boolean(this.reconnectUrl),
      connectionAttempts: this.connectionAttempts,
      reconnectCount: this.reconnectCount,
      lastConnectedAt: this.lastConnectedAt,
      lastDisconnectedAt: this.lastDisconnectedAt,
      lastKeepaliveAt: this.lastKeepaliveAt,
      keepaliveTimeoutSeconds: this.keepaliveTimeoutSeconds,
      keepaliveStale: this.isKeepaliveStale(now),
      lastNotificationAt: this.lastNotificationAt,
      lastRevocationAt: this.lastRevocationAt,
      lastError: this.lastError,
      subscriptionResults: Array.from(this.subscriptionResults.values())
    };
  }
}
