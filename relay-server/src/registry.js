export class RelayRegistry {
  constructor() {
    this.records = new Map();
  }

  register({ userId, deviceToken, services, credentials }) {
    this.records.set(userId, {
      userId,
      deviceToken,
      services,
      credentials: Array.isArray(credentials) ? credentials : [],
      directConnectionActive: false,
      updatedAt: new Date()
    });
  }

  setPresence({ userId, directConnectionActive }) {
    const record = this.records.get(userId);
    if (!record) return;
    record.directConnectionActive = directConnectionActive;
    record.updatedAt = new Date();
  }

  updateDeviceToken({ userId, deviceToken }) {
    const record = this.records.get(userId);
    if (!record || !deviceToken) return;
    record.deviceToken = deviceToken;
    record.updatedAt = new Date();
  }

  get(userId) {
    return this.records.get(userId);
  }

  count() {
    return this.records.size;
  }
}
