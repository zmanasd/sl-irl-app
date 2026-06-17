import { createHash } from "node:crypto";

export function deviceTokenDiagnostics(deviceToken) {
  if (typeof deviceToken !== "string" || deviceToken.length === 0) {
    return {
      hasDeviceToken: false,
      deviceTokenLength: 0,
      deviceTokenFingerprint: null
    };
  }

  return {
    hasDeviceToken: true,
    deviceTokenLength: deviceToken.length,
    deviceTokenFingerprint: createHash("sha256")
      .update(deviceToken)
      .digest("hex")
      .slice(0, 12)
  };
}

export class RelayRegistry {
  constructor({ storage = null } = {}) {
    this.storage = storage;
    this.records = new Map();
    this.twitchOAuthStates = new Map();
    this.deliveryAttempts = [];
    this.tokenRefreshAttempts = [];
    this.providerMessages = [];
    this.load();
  }

  load() {
    if (!this.storage) return;
    const snapshot = this.storage.snapshot();

    for (const record of snapshot.records) {
      this.records.set(record.userId, {
        ...record,
        updatedAt: record.updatedAt ? new Date(record.updatedAt) : new Date()
      });
    }

    for (const state of snapshot.twitchOAuthStates) {
      this.twitchOAuthStates.set(state.state, state);
    }

    this.deliveryAttempts = Array.isArray(snapshot.deliveryAttempts)
      ? snapshot.deliveryAttempts
      : [];
    this.tokenRefreshAttempts = Array.isArray(snapshot.tokenRefreshAttempts)
      ? snapshot.tokenRefreshAttempts
      : [];
    this.providerMessages = Array.isArray(snapshot.providerMessages)
      ? snapshot.providerMessages
      : [];
  }

  persist() {
    if (!this.storage) return;
    this.storage.replace({
      records: Array.from(this.records.values()).map((record) => ({
        ...record,
        updatedAt: record.updatedAt?.toISOString?.() ?? record.updatedAt
      })),
      twitchOAuthStates: Array.from(this.twitchOAuthStates.values()),
      deliveryAttempts: this.deliveryAttempts,
      tokenRefreshAttempts: this.tokenRefreshAttempts,
      providerMessages: this.providerMessages
    });
  }

  register({ userId, deviceToken, services, credentials }) {
    const existing = this.records.get(userId);
    this.records.set(userId, {
      ...existing,
      userId,
      deviceToken,
      services,
      credentials: Array.isArray(credentials) ? credentials : [],
      updatedAt: new Date()
    });
    this.persist();
  }

  updateDeviceToken({ userId, deviceToken }) {
    const record = this.records.get(userId);
    if (!record || !deviceToken) return;
    record.deviceToken = deviceToken;
    record.updatedAt = new Date();
    this.persist();
  }

  saveTwitchOAuthState(stateRecord) {
    this.twitchOAuthStates.set(stateRecord.state, stateRecord);
    this.persist();
  }

  consumeTwitchOAuthState(state) {
    const stateRecord = this.twitchOAuthStates.get(state);
    if (!stateRecord) return null;
    this.twitchOAuthStates.delete(state);
    this.persist();
    return stateRecord;
  }

  setTwitchAuth({ userId, twitchUser, tokenPayload, scopes }) {
    const record = this.records.get(userId) ?? {
      userId,
      services: [],
      credentials: []
    };

    const expiresIn = Number(tokenPayload.expires_in ?? 0);
    const expiresAt = expiresIn > 0
      ? new Date(Date.now() + expiresIn * 1000).toISOString()
      : null;

    record.twitch = {
      broadcasterId: twitchUser.id,
      login: twitchUser.login,
      displayName: twitchUser.display_name ?? twitchUser.login,
      accessToken: tokenPayload.access_token,
      refreshToken: tokenPayload.refresh_token,
      scopes: Array.isArray(tokenPayload.scope) ? tokenPayload.scope : scopes,
      expiresAt,
      updatedAt: new Date().toISOString()
    };

    record.services = Array.from(new Set([...(record.services ?? []), "twitch_native"]));
    record.credentials = [
      ...(record.credentials ?? []).filter((credential) => credential.service !== "twitch_native"),
      {
        service: "twitch_native",
        type: "oauth",
        value: tokenPayload.access_token
      }
    ];
    record.updatedAt = new Date();

    this.records.set(userId, record);
    this.persist();
    return record;
  }

  updateTwitchToken({ userId, tokenPayload }) {
    const record = this.records.get(userId);
    if (!record?.twitch) return null;

    const expiresIn = Number(tokenPayload.expires_in ?? 0);
    record.twitch.accessToken = tokenPayload.access_token;
    record.twitch.refreshToken = tokenPayload.refresh_token ?? record.twitch.refreshToken;
    record.twitch.scopes = Array.isArray(tokenPayload.scope)
      ? tokenPayload.scope
      : record.twitch.scopes;
    record.twitch.expiresAt = expiresIn > 0
      ? new Date(Date.now() + expiresIn * 1000).toISOString()
      : record.twitch.expiresAt;
    record.twitch.updatedAt = new Date().toISOString();
    record.updatedAt = new Date();

    record.credentials = [
      ...(record.credentials ?? []).filter((credential) => credential.service !== "twitch_native"),
      {
        service: "twitch_native",
        type: "oauth",
        value: tokenPayload.access_token
      }
    ];

    this.persist();
    return record;
  }

  get(userId) {
    return this.records.get(userId);
  }

  count() {
    return this.records.size;
  }

  userIds() {
    return Array.from(this.records.keys());
  }

  recordDeliveryAttempt({ userId, alert, status, result = null, error = null, deviceToken = null }) {
    const device = deviceTokenDiagnostics(deviceToken);
    const attempt = {
      userId,
      correlationId: alert?.correlationId ?? null,
      providerMessageId: alert?.providerMessageId ?? alert?.alert_id ?? null,
      source: alert?.source ?? null,
      type: alert?.type ?? null,
      status,
      deviceTokenFingerprint: device.deviceTokenFingerprint,
      deviceTokenLength: device.deviceTokenLength,
      apnsIds: Array.isArray(result?.apnsIds) ? result.apnsIds : [],
      apnsSent: result?.summary?.sent ?? null,
      apnsFailed: result?.summary?.failed ?? null,
      apnsFailedReasons: Array.isArray(result?.summary?.failedReasons)
        ? result.summary.failedReasons
        : [],
      error: error?.message ?? result?.error ?? null,
      createdAt: new Date().toISOString()
    };

    this.deliveryAttempts.push(attempt);
    if (this.deliveryAttempts.length > 200) {
      this.deliveryAttempts = this.deliveryAttempts.slice(-100);
    }
    this.persist();
    return attempt;
  }

  findDeliveryAttempts({ correlationId = null, providerMessageId = null, userId = null } = {}) {
    return this.deliveryAttempts.filter((attempt) => {
      if (userId && attempt.userId !== userId) return false;
      if (correlationId && attempt.correlationId === correlationId) return true;
      if (providerMessageId && attempt.providerMessageId === providerMessageId) return true;
      return false;
    });
  }

  twitchRecordsNeedingRefresh({
    now = new Date(),
    refreshWindowMs = 10 * 60 * 1000
  } = {}) {
    const nowMs = now.getTime();

    return Array.from(this.records.values()).filter((record) => {
      if (!record.twitch?.refreshToken) return false;
      if (!record.twitch.expiresAt) return true;

      const expiresAtMs = Date.parse(record.twitch.expiresAt);
      if (Number.isNaN(expiresAtMs)) return true;

      return expiresAtMs - nowMs <= refreshWindowMs;
    });
  }

  recordTwitchTokenRefreshAttempt({
    userId,
    status,
    expiresAt = null,
    scopes = [],
    error = null,
    now = new Date()
  }) {
    const attempt = {
      userId,
      status,
      expiresAt,
      scopes,
      error: error?.message ?? error ?? null,
      createdAt: now.toISOString()
    };

    this.tokenRefreshAttempts.push(attempt);
    if (this.tokenRefreshAttempts.length > 200) {
      this.tokenRefreshAttempts = this.tokenRefreshAttempts.slice(-100);
    }
    this.persist();
    return attempt;
  }

  reserveProviderMessage({ userId, alert, now = new Date() }) {
    const providerMessageId = alert?.providerMessageId ?? alert?.alert_id ?? null;
    const source = alert?.source ?? null;
    if (!providerMessageId || !source) {
      return { reserved: true, duplicate: false, providerMessageId, source };
    }

    const existing = this.providerMessages.find((message) => (
      message.userId === userId
      && message.source === source
      && message.providerMessageId === providerMessageId
    ));

    if (existing) {
      return {
        reserved: false,
        duplicate: true,
        providerMessageId,
        source,
        firstSeenAt: existing.firstSeenAt
      };
    }

    const entry = {
      userId,
      source,
      providerMessageId,
      firstSeenAt: now.toISOString()
    };
    this.providerMessages.push(entry);
    if (this.providerMessages.length > 500) {
      this.providerMessages = this.providerMessages.slice(-250);
    }
    this.persist();
    return { reserved: true, duplicate: false, ...entry };
  }

  diagnostics() {
    const users = Array.from(this.records.values()).map((record) => ({
      userId: record.userId,
      ...deviceTokenDiagnostics(record.deviceToken),
      services: record.services ?? [],
      updatedAt: record.updatedAt?.toISOString?.() ?? record.updatedAt,
      twitch: record.twitch ? {
        broadcasterId: record.twitch.broadcasterId,
        login: record.twitch.login,
        displayName: record.twitch.displayName,
        hasAccessToken: Boolean(record.twitch.accessToken),
        hasRefreshToken: Boolean(record.twitch.refreshToken),
        scopes: record.twitch.scopes ?? [],
        expiresAt: record.twitch.expiresAt,
        updatedAt: record.twitch.updatedAt
      } : null
    }));

    return {
      users,
      pendingTwitchOAuthStates: this.twitchOAuthStates.size,
      recentDeliveryAttempts: this.deliveryAttempts.slice(-20),
      recentTokenRefreshAttempts: this.tokenRefreshAttempts.slice(-20),
      providerMessageDedupe: {
        tracked: this.providerMessages.length,
        recent: this.providerMessages.slice(-20)
      }
    };
  }
}
