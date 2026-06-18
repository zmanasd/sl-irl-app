import { createHash, randomBytes, randomUUID } from "node:crypto";
import { decryptSecret, encryptSecret, secretEncryptionDiagnostics } from "./secret-crypto.js";

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
  constructor({
    storage = null,
    secretEncryptionKey = process.env.RELAY_TOKEN_ENCRYPTION_KEY ?? process.env.RELAY_STORAGE_ENCRYPTION_KEY,
    secretEncryptionKeyId = process.env.RELAY_TOKEN_ENCRYPTION_KEY_ID ?? "default"
  } = {}) {
    this.storage = storage;
    this.secretEncryptionKey = secretEncryptionKey;
    this.secretEncryptionKeyId = secretEncryptionKeyId;
    this.secretEncryption = secretEncryptionDiagnostics({
      key: secretEncryptionKey,
      keyId: secretEncryptionKeyId
    });
    this.records = new Map();
    this.twitchOAuthStates = new Map();
    this.deliveryAttempts = [];
    this.tokenRefreshAttempts = [];
    this.providerMessages = [];
    this.appReceipts = [];
    this.operations = {};
    this.load();
  }

  load() {
    if (!this.storage) return;
    const snapshot = this.storage.snapshot();

    for (const record of snapshot.records) {
      const decryptedRecord = unprotectRecord(record, {
        key: this.secretEncryptionKey
      });
      this.records.set(record.userId, {
        ...decryptedRecord,
        updatedAt: decryptedRecord.updatedAt ? new Date(decryptedRecord.updatedAt) : new Date()
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
    this.appReceipts = Array.isArray(snapshot.appReceipts)
      ? snapshot.appReceipts
      : [];
    this.operations = snapshot.operations && typeof snapshot.operations === "object"
      ? snapshot.operations
      : {};
  }

  persist() {
    if (!this.storage) return;
    const result = this.storage.replace({
      records: Array.from(this.records.values()).map((record) => ({
        ...protectRecord(record, {
          key: this.secretEncryptionKey,
          keyId: this.secretEncryptionKeyId
        }),
        updatedAt: record.updatedAt?.toISOString?.() ?? record.updatedAt
      })),
      twitchOAuthStates: Array.from(this.twitchOAuthStates.values()),
      deliveryAttempts: this.deliveryAttempts,
      tokenRefreshAttempts: this.tokenRefreshAttempts,
      providerMessages: this.providerMessages,
      appReceipts: this.appReceipts,
      operations: this.operations
    });
    this.lastPersist = result && typeof result.then === "function"
      ? result
      : Promise.resolve();
    return this.lastPersist;
  }

  async flush() {
    if (this.lastPersist) {
      await this.lastPersist;
      this.lastPersist = null;
    }
    if (typeof this.storage?.flush === "function") {
      await this.storage.flush();
    }
  }

  register({ userId, deviceToken, services, credentials }) {
    const existing = this.records.get(userId);
    const devices = upsertDevice(existing?.devices, {
      deviceToken,
      apnsEnvironment: null,
      appBuild: null,
      appVersion: null
    });
    this.records.set(userId, {
      ...existing,
      userId,
      deviceToken,
      devices,
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
    record.devices = upsertDevice(record.devices, {
      deviceToken,
      apnsEnvironment: null,
      appBuild: null,
      appVersion: null
    });
    record.updatedAt = new Date();
    this.persist();
  }

  upsertAppleAccount({
    appleSubject,
    email = null,
    fullName = null,
    now = new Date()
  }) {
    if (!appleSubject) {
      throw new Error("appleSubject is required.");
    }

    const existing = Array.from(this.records.values()).find((record) => (
      record.account?.provider === "apple"
      && record.account.providerSubject === appleSubject
    ));
    const userId = existing?.userId ?? `user_${randomUUID()}`;
    const record = existing ?? {
      userId,
      services: [],
      credentials: [],
      devices: []
    };

    record.account = {
      provider: "apple",
      providerSubject: appleSubject,
      email: email ?? record.account?.email ?? null,
      fullName: fullName ?? record.account?.fullName ?? null,
      createdAt: record.account?.createdAt ?? now.toISOString(),
      updatedAt: now.toISOString()
    };
    record.updatedAt = now;

    this.records.set(userId, record);
    this.persist();
    return record;
  }

  createSession({
    userId,
    ttlSeconds = 60 * 60 * 24 * 30,
    now = new Date()
  }) {
    const record = this.records.get(userId);
    if (!record) {
      throw new Error("Cannot create a session for an unknown user.");
    }

    const token = randomBytes(32).toString("base64url");
    const session = {
      id: `session_${randomUUID()}`,
      tokenHash: hashSecret(token),
      createdAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + ttlSeconds * 1000).toISOString()
    };

    record.sessions = [
      ...activeSessions(record.sessions, now),
      session
    ].slice(-10);
    record.updatedAt = now;
    this.persist();

    return {
      token,
      session: {
        id: session.id,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt
      }
    };
  }

  getSession(token, now = new Date()) {
    if (!token) return null;
    const tokenHash = hashSecret(token);

    for (const record of this.records.values()) {
      const session = activeSessions(record.sessions, now)
        .find((candidate) => candidate.tokenHash === tokenHash);
      if (session) {
        return {
          userId: record.userId,
          sessionId: session.id,
          expiresAt: session.expiresAt
        };
      }
    }

    return null;
  }

  upsertDevice({
    userId,
    deviceToken,
    apnsEnvironment = null,
    appBuild = null,
    appVersion = null,
    now = new Date()
  }) {
    const record = this.records.get(userId);
    if (!record) return null;

    record.devices = upsertDevice(record.devices, {
      deviceToken,
      apnsEnvironment,
      appBuild,
      appVersion
    }, now);
    record.deviceToken = deviceToken;
    record.updatedAt = now;
    this.persist();

    const saved = record.devices.find((device) => device.deviceToken === deviceToken);
    return saved ? safeDevice(saved) : null;
  }

  removeDevice({ userId, deviceId }) {
    const record = this.records.get(userId);
    if (!record) return false;

    const before = Array.isArray(record.devices) ? record.devices.length : 0;
    record.devices = (record.devices ?? []).filter((device) => device.id !== deviceId);
    if (record.devices.length === 0) {
      record.deviceToken = null;
    } else if (!record.devices.some((device) => device.deviceToken === record.deviceToken)) {
      record.deviceToken = record.devices.at(-1)?.deviceToken ?? null;
    }
    record.updatedAt = new Date();
    this.persist();
    return record.devices.length !== before;
  }

  updatePreferences({ userId, preferences = {}, now = new Date() }) {
    const record = this.records.get(userId);
    if (!record) return null;
    record.preferences = {
      ...(record.preferences ?? {}),
      ...preferences,
      updatedAt: now.toISOString()
    };
    record.updatedAt = now;
    this.persist();
    return safePreferences(record.preferences);
  }

  disconnectTwitch(userId) {
    const record = this.records.get(userId);
    if (!record) return null;
    delete record.twitch;
    record.services = (record.services ?? []).filter((service) => service !== "twitch_native");
    record.credentials = (record.credentials ?? [])
      .filter((credential) => credential.service !== "twitch_native");
    record.updatedAt = new Date();
    this.persist();
    return record;
  }

  deleteAccount(userId) {
    const existed = this.records.delete(userId);
    this.twitchOAuthStates = new Map(
      Array.from(this.twitchOAuthStates.entries())
        .filter(([, state]) => state.userId !== userId)
    );
    this.deliveryAttempts = this.deliveryAttempts.filter((attempt) => attempt.userId !== userId);
    this.tokenRefreshAttempts = this.tokenRefreshAttempts
      .filter((attempt) => attempt.userId !== userId);
    this.providerMessages = this.providerMessages
      .filter((message) => message.userId !== userId);
    this.appReceipts = this.appReceipts
      .filter((receipt) => receipt.userId !== userId);
    this.persist();
    return existed;
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

  recordDeliveryAttempt({
    userId,
    alert,
    status,
    result = null,
    error = null,
    deviceToken = null,
    jobId = null,
    queueAttempt = null,
    nextRetryAttempt = null
  }) {
    const device = deviceTokenDiagnostics(deviceToken);
    const attempt = {
      userId,
      correlationId: alert?.correlationId ?? null,
      providerMessageId: alert?.providerMessageId ?? alert?.alert_id ?? null,
      source: alert?.source ?? null,
      type: alert?.type ?? null,
      status,
      jobId: jobId ?? result?.jobId ?? null,
      queueAttempt,
      nextRetryAttempt,
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
    const correlationId = alert?.correlationId ?? null;
    if (!providerMessageId || !source) {
      return { reserved: true, duplicate: false, providerMessageId, source, correlationId };
    }

    const existing = this.providerMessages.find((message) => (
      message.userId === userId
      && message.source === source
      && message.providerMessageId === providerMessageId
    ));

    if (existing) {
      existing.duplicateCount = Number(existing.duplicateCount ?? 0) + 1;
      existing.lastDuplicateAt = now.toISOString();
      this.persist();
      return {
        reserved: false,
        duplicate: true,
        providerMessageId,
        source,
        correlationId: existing.correlationId ?? correlationId,
        duplicateCount: existing.duplicateCount,
        firstSeenAt: existing.firstSeenAt
      };
    }

    const entry = {
      userId,
      source,
      providerMessageId,
      correlationId,
      type: alert?.type ?? null,
      firstSeenAt: now.toISOString()
    };
    this.providerMessages.push(entry);
    if (this.providerMessages.length > 500) {
      this.providerMessages = this.providerMessages.slice(-250);
    }
    this.persist();
    return { reserved: true, duplicate: false, ...entry };
  }

  recordAppReceipt({
    userId,
    correlationId,
    providerMessageId = null,
    status = "received",
    appReceivedAt = null,
    appBuild = null,
    appVersion = null,
    now = new Date()
  }) {
    const receipt = {
      userId,
      correlationId,
      providerMessageId,
      status,
      appReceivedAt,
      appBuild,
      appVersion,
      createdAt: now.toISOString()
    };

    this.appReceipts.push(receipt);
    if (this.appReceipts.length > 500) {
      this.appReceipts = this.appReceipts.slice(-250);
    }
    this.persist();
    return receipt;
  }

  findAppReceipts({ correlationId = null, providerMessageId = null, userId = null } = {}) {
    return this.appReceipts.filter((receipt) => {
      if (userId && receipt.userId !== userId) return false;
      if (correlationId && receipt.correlationId === correlationId) return true;
      if (providerMessageId && receipt.providerMessageId === providerMessageId) return true;
      return false;
    });
  }

  findProviderMessages({ correlationId = null, providerMessageId = null, userId = null } = {}) {
    return this.providerMessages.filter((message) => {
      if (userId && message.userId !== userId) return false;
      if (correlationId && message.correlationId === correlationId) return true;
      if (providerMessageId && message.providerMessageId === providerMessageId) return true;
      return false;
    });
  }

  deliveryTrace({ correlationId = null, providerMessageId = null, userId = null } = {}) {
    const providerMessages = this.findProviderMessages({ correlationId, providerMessageId, userId });
    const deliveryAttempts = this.findDeliveryAttempts({ correlationId, providerMessageId, userId });
    const appReceipts = this.findAppReceipts({ correlationId, providerMessageId, userId });
    const statuses = new Set(deliveryAttempts.map((attempt) => attempt.status));

    return {
      providerMessages,
      deliveryAttempts,
      appReceipts,
      stages: {
        providerReceived: providerMessages.length > 0,
        queued: statuses.has("queued") || statuses.has("retry_scheduled"),
        apnsAttempted: deliveryAttempts.some((attempt) => (
          attempt.status === "sent"
          || attempt.status === "failed"
          || attempt.status === "retry_scheduled"
        )),
        apnsSent: statuses.has("sent"),
        duplicateSuppressed: statuses.has("duplicate_provider_message"),
        appReceived: appReceipts.some((receipt) => receipt.status === "received")
      }
    };
  }

  recordWorkerHeartbeat({
    workerId = "default",
    status = "alive",
    processed = null,
    error = null,
    now = new Date()
  } = {}) {
    const heartbeat = {
      workerId,
      status,
      processed,
      error: error?.message ?? error ?? null,
      createdAt: now.toISOString()
    };
    this.operations.workerHeartbeats = {
      ...(this.operations.workerHeartbeats ?? {}),
      [workerId]: heartbeat
    };
    this.persist();
    return heartbeat;
  }

  recordProofCheck({
    status,
    checks = [],
    userId = null,
    correlationId = null,
    now = new Date()
  }) {
    const proofCheck = {
      status,
      userId,
      correlationId,
      checks: checks.map((check) => ({
        name: check.name,
        ok: Boolean(check.ok),
        category: check.category ?? null
      })),
      createdAt: now.toISOString()
    };
    const recent = Array.isArray(this.operations.proofChecks)
      ? this.operations.proofChecks
      : [];
    this.operations.proofChecks = [...recent, proofCheck].slice(-30);
    this.persist();
    return proofCheck;
  }

  diagnostics() {
    const users = Array.from(this.records.values()).map((record) => ({
      userId: record.userId,
      ...deviceTokenDiagnostics(record.deviceToken),
      account: record.account ? {
        provider: record.account.provider,
        hasProviderSubject: Boolean(record.account.providerSubject),
        hasEmail: Boolean(record.account.email),
        createdAt: record.account.createdAt,
        updatedAt: record.account.updatedAt
      } : null,
      devices: Array.isArray(record.devices)
        ? record.devices.map(safeDevice)
        : [],
      preferences: safePreferences(record.preferences),
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
      },
      appReceipts: {
        tracked: this.appReceipts.length,
        recent: this.appReceipts.slice(-20)
      },
      operations: {
        workerHeartbeats: this.operations.workerHeartbeats ?? {},
        proofChecks: Array.isArray(this.operations.proofChecks)
          ? this.operations.proofChecks.slice(-10)
          : []
      },
      secretEncryption: this.secretEncryption
    };
  }
}

function hashSecret(value) {
  return createHash("sha256").update(value).digest("hex");
}

function activeSessions(sessions = [], now = new Date()) {
  return (Array.isArray(sessions) ? sessions : []).filter((session) => {
    const expiresAt = Date.parse(session.expiresAt);
    return !Number.isNaN(expiresAt) && expiresAt > now.getTime();
  });
}

function upsertDevice(devices = [], nextDevice, now = new Date()) {
  if (!nextDevice?.deviceToken) {
    return Array.isArray(devices) ? devices : [];
  }

  const existing = (Array.isArray(devices) ? devices : [])
    .filter((device) => device.deviceToken !== nextDevice.deviceToken);
  return [
    ...existing,
    {
      id: nextDevice.id ?? `device_${randomUUID()}`,
      deviceToken: nextDevice.deviceToken,
      apnsEnvironment: nextDevice.apnsEnvironment ?? null,
      appBuild: nextDevice.appBuild ?? null,
      appVersion: nextDevice.appVersion ?? null,
      createdAt: nextDevice.createdAt ?? now.toISOString(),
      updatedAt: nextDevice.updatedAt ?? now.toISOString()
    }
  ].slice(-10);
}

function safeDevice(device) {
  return {
    id: device.id,
    ...deviceTokenDiagnostics(device.deviceToken),
    apnsEnvironment: device.apnsEnvironment ?? null,
    appBuild: device.appBuild ?? null,
    appVersion: device.appVersion ?? null,
    createdAt: device.createdAt ?? null,
    updatedAt: device.updatedAt ?? null
  };
}

function safePreferences(preferences) {
  if (!preferences) return null;
  return {
    alertsEnabled: preferences.alertsEnabled ?? null,
    soundEnabled: preferences.soundEnabled ?? null,
    ttsEnabled: preferences.ttsEnabled ?? null,
    minimumBits: preferences.minimumBits ?? null,
    updatedAt: preferences.updatedAt ?? null
  };
}

function protectRecord(record, { key, keyId }) {
  const protectedRecord = structuredClone(record);

  protectedRecord.deviceToken = encryptSecret(protectedRecord.deviceToken, { key, keyId });
  protectedRecord.devices = (protectedRecord.devices ?? []).map((device) => ({
    ...device,
    deviceToken: encryptSecret(device.deviceToken, { key, keyId })
  }));
  protectedRecord.credentials = (protectedRecord.credentials ?? []).map((credential) => ({
    ...credential,
    value: encryptSecret(credential.value, { key, keyId })
  }));

  if (protectedRecord.twitch) {
    protectedRecord.twitch = {
      ...protectedRecord.twitch,
      accessToken: encryptSecret(protectedRecord.twitch.accessToken, { key, keyId }),
      refreshToken: encryptSecret(protectedRecord.twitch.refreshToken, { key, keyId })
    };
  }

  if (protectedRecord.account) {
    protectedRecord.account = {
      ...protectedRecord.account,
      providerSubject: encryptSecret(protectedRecord.account.providerSubject, { key, keyId }),
      email: encryptSecret(protectedRecord.account.email, { key, keyId }),
      fullName: encryptSecret(protectedRecord.account.fullName, { key, keyId })
    };
  }

  return protectedRecord;
}

function unprotectRecord(record, { key }) {
  const unprotectedRecord = structuredClone(record);

  unprotectedRecord.deviceToken = decryptSecret(unprotectedRecord.deviceToken, { key });
  unprotectedRecord.devices = (unprotectedRecord.devices ?? []).map((device) => ({
    ...device,
    deviceToken: decryptSecret(device.deviceToken, { key })
  }));
  unprotectedRecord.credentials = (unprotectedRecord.credentials ?? []).map((credential) => ({
    ...credential,
    value: decryptSecret(credential.value, { key })
  }));

  if (unprotectedRecord.twitch) {
    unprotectedRecord.twitch = {
      ...unprotectedRecord.twitch,
      accessToken: decryptSecret(unprotectedRecord.twitch.accessToken, { key }),
      refreshToken: decryptSecret(unprotectedRecord.twitch.refreshToken, { key })
    };
  }

  if (unprotectedRecord.account) {
    unprotectedRecord.account = {
      ...unprotectedRecord.account,
      providerSubject: decryptSecret(unprotectedRecord.account.providerSubject, { key }),
      email: decryptSecret(unprotectedRecord.account.email, { key }),
      fullName: decryptSecret(unprotectedRecord.account.fullName, { key })
    };
  }

  return unprotectedRecord;
}
