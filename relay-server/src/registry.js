export class RelayRegistry {
  constructor() {
    this.records = new Map();
  }

  register({ userId, deviceToken, services }) {
    this.records.set(userId, {
      userId,
      deviceToken,
      services,
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

  get(userId) {
    return this.records.get(userId);
  }

  count() {
    return this.records.size;
  }
}
