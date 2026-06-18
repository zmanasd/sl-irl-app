export class RelayConnectorManager {
  constructor({ registry, logger, sendAlert }) {
    this.registry = registry;
    this.logger = logger;
    this.sendAlert = sendAlert;
    this.connectors = new Map();
    this.lastSyncAllAt = null;
    this.lastSyncAllResults = [];
  }

  async syncForUser(userId) {
    const record = this.registry.get(userId);
    if (!record) return;

    const credentials = Array.isArray(record.credentials) ? record.credentials : [];
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

      const { TwitchEventSubConnector } = await import("./twitch.js");
      const connector = new TwitchEventSubConnector({
        userId,
        token: credential.value,
        clientId: process.env.TWITCH_CLIENT_ID,
        logger: this.logger,
        onAlert: (alert) => this.handleAlert(userId, alert)
      });

      await connector.start();
      this.connectors.set(key, connector);
    }
  }

  async syncAllUsers() {
    const userIds = typeof this.registry.userIds === "function" ? this.registry.userIds() : [];
    const results = [];

    for (const userId of userIds) {
      try {
        await this.syncForUser(userId);
        results.push({ userId, ok: true });
      } catch (error) {
        this.logger.error({ userId, error: error?.message }, "Failed to sync relay connectors for user.");
        results.push({
          userId,
          ok: false,
          error: error?.message ?? "Connector sync failed."
        });
      }
    }

    this.lastSyncAllAt = new Date().toISOString();
    this.lastSyncAllResults = results.slice(-50);
    return results;
  }

  diagnostics() {
    return Array.from(this.connectors.entries()).map(([key, connector]) => {
      if (typeof connector.diagnostics === "function") {
        return {
          key,
          ...connector.diagnostics()
        };
      }

      return {
        key,
        service: key.split(":").slice(1).join(":"),
        hasDiagnostics: false
      };
    });
  }

  recoveryDiagnostics() {
    return {
      lastSyncAllAt: this.lastSyncAllAt,
      syncedUsers: this.lastSyncAllResults.filter((result) => result.ok).length,
      failedUsers: this.lastSyncAllResults.filter((result) => !result.ok).length,
      results: this.lastSyncAllResults
    };
  }

  async handleAlert(userId, alert) {
    const record = this.registry.get(userId);
    if (!record) return;

    const providerMessage = this.registry.reserveProviderMessage({ userId, alert });
    if (providerMessage.duplicate) {
      this.logger.info(
        { userId, providerMessageId: providerMessage.providerMessageId },
        "Skipping duplicate provider message."
      );
      this.registry.recordDeliveryAttempt({
        userId,
        alert,
        status: "duplicate_provider_message",
        deviceToken: record.deviceToken
      });
      await this.registry.flush?.();
      return;
    }

    try {
      const result = await this.sendAlert({
        deviceToken: record.deviceToken,
        alert,
        userId
      });
      this.registry.recordDeliveryAttempt({
        userId,
        alert,
        status: result?.queued ? "queued" : (result?.ok ? "sent" : "failed"),
        result,
        deviceToken: record.deviceToken
      });
      await this.registry.flush?.();
    } catch (error) {
      this.registry.recordDeliveryAttempt({
        userId,
        alert,
        status: "failed",
        error,
        deviceToken: record.deviceToken
      });
      await this.registry.flush?.();
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
