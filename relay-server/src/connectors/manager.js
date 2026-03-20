import { StreamlabsConnector } from "./streamlabs.js";
import { StreamElementsConnector } from "./streamelements.js";
import { TwitchEventSubConnector } from "./twitch.js";

export class RelayConnectorManager {
  constructor({ registry, logger, sendAlert }) {
    this.registry = registry;
    this.logger = logger;
    this.sendAlert = sendAlert;
    this.connectors = new Map();
  }

  syncForUser(userId) {
    const record = this.registry.get(userId);
    if (!record) return;

    const credentials = Array.isArray(record.credentials) ? record.credentials : [];
    for (const credential of credentials) {
      if (credential.service !== "streamlabs") continue;
      const token = credential.type === "socket" ? credential.value : null;
      if (!token) continue;

      const key = `${userId}:streamlabs`;
      if (this.connectors.has(key)) {
        const existing = this.connectors.get(key);
        if (existing?.token === token) continue;
        existing?.stop();
        this.connectors.delete(key);
      }

      const connector = new StreamlabsConnector({
        userId,
        token,
        logger: this.logger,
        onAlert: (alert) => this.handleAlert(userId, alert)
      });

      connector.start();
      this.connectors.set(key, connector);
    }

    for (const credential of credentials) {
      if (credential.service !== "stream_elements") continue;

      let tokenType = null;
      if (credential.type === "oauth") tokenType = "oauth";
      if (credential.type === "jwt") tokenType = "jwt";
      if (credential.type === "socket") tokenType = "apikey";

      const token = credential.value;
      if (!token || !tokenType) continue;

      const key = `${userId}:stream_elements`;
      if (this.connectors.has(key)) {
        const existing = this.connectors.get(key);
        if (existing?.token === token && existing?.tokenType === tokenType) continue;
        existing?.stop();
        this.connectors.delete(key);
      }

      const connector = new StreamElementsConnector({
        userId,
        token,
        tokenType,
        logger: this.logger,
        onAlert: (alert) => this.handleAlert(userId, alert)
      });

      connector.start();
      this.connectors.set(key, connector);
    }

    for (const credential of credentials) {
      if (credential.service !== "twitch_native") continue;
      if (credential.type !== "oauth") continue;
      if (!credential.value) continue;

      const key = `${userId}:twitch_native`;
      if (this.connectors.has(key)) {
        const existing = this.connectors.get(key);
        if (existing?.token === credential.value) continue;
        existing?.stop();
        this.connectors.delete(key);
      }

      const connector = new TwitchEventSubConnector({
        userId,
        token: credential.value,
        clientId: process.env.TWITCH_CLIENT_ID,
        logger: this.logger,
        onAlert: (alert) => this.handleAlert(userId, alert)
      });

      connector.start();
      this.connectors.set(key, connector);
    }
  }

  async handleAlert(userId, alert) {
    const record = this.registry.get(userId);
    if (!record) return;

    if (record.directConnectionActive) {
      this.logger.info({ userId }, "Skipping push; direct connection active.");
      return;
    }

    try {
      await this.sendAlert({
        deviceToken: record.deviceToken,
        alert
      });
    } catch (error) {
      this.logger.error({ userId, error: error?.message }, "Failed to forward alert.");
    }
  }

  stopUser(userId) {
    const prefix = `${userId}:`;
    for (const [key, connector] of this.connectors) {
      if (key.startsWith(prefix)) {
        connector.stop();
        this.connectors.delete(key);
      }
    }
  }
}
