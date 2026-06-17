import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import fs from "fs";
import path from "path";

const ENCRYPTION_VERSION = 1;
const ENCRYPTION_ALGORITHM = "aes-256-gcm";

function decodeEncryptionKey(key) {
  if (!key) return null;

  const encodings = ["base64", "hex"];
  for (const encoding of encodings) {
    const decoded = Buffer.from(key, encoding);
    if (decoded.length === 32) return decoded;
  }

  throw new Error("RELAY_STORAGE_ENCRYPTION_KEY must decode to 32 bytes.");
}

export function createEncryptedSnapshot({ data, key, iv = randomBytes(12) }) {
  const decodedKey = decodeEncryptionKey(key);
  if (!decodedKey) return data;

  const cipher = createCipheriv(ENCRYPTION_ALGORITHM, decodedKey, iv);
  const plaintext = Buffer.from(JSON.stringify(data), "utf8");
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);

  return {
    encrypted: true,
    version: ENCRYPTION_VERSION,
    algorithm: ENCRYPTION_ALGORITHM,
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    data: ciphertext.toString("base64")
  };
}

export function readEncryptedSnapshot({ payload, key }) {
  if (!payload?.encrypted) return payload;

  const decodedKey = decodeEncryptionKey(key);
  if (!decodedKey) {
    throw new Error("RELAY_STORAGE_ENCRYPTION_KEY is required to read encrypted relay storage.");
  }

  if (payload.version !== ENCRYPTION_VERSION || payload.algorithm !== ENCRYPTION_ALGORITHM) {
    throw new Error("Unsupported encrypted relay storage format.");
  }

  const decipher = createDecipheriv(
    ENCRYPTION_ALGORITHM,
    decodedKey,
    Buffer.from(payload.iv, "base64")
  );
  decipher.setAuthTag(Buffer.from(payload.tag, "base64"));

  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(payload.data, "base64")),
    decipher.final()
  ]).toString("utf8");

  return JSON.parse(plaintext);
}

export class LocalJsonStore {
  constructor(filePath, { encryptionKey = process.env.RELAY_STORAGE_ENCRYPTION_KEY } = {}) {
    this.filePath = filePath;
    this.encryptionKey = encryptionKey;
    this.encrypted = Boolean(encryptionKey);
    this.data = {
      records: [],
      twitchOAuthStates: [],
      deliveryAttempts: [],
      tokenRefreshAttempts: [],
      providerMessages: []
    };
    this.load();
  }

  load() {
    if (!this.filePath || !fs.existsSync(this.filePath)) return;

    const raw = fs.readFileSync(this.filePath, "utf8");
    if (!raw.trim()) return;

    const parsed = readEncryptedSnapshot({
      payload: JSON.parse(raw),
      key: this.encryptionKey
    });
    this.data = {
      records: Array.isArray(parsed.records) ? parsed.records : [],
      twitchOAuthStates: Array.isArray(parsed.twitchOAuthStates)
        ? parsed.twitchOAuthStates
        : [],
      deliveryAttempts: Array.isArray(parsed.deliveryAttempts)
        ? parsed.deliveryAttempts
        : [],
      tokenRefreshAttempts: Array.isArray(parsed.tokenRefreshAttempts)
        ? parsed.tokenRefreshAttempts
        : [],
      providerMessages: Array.isArray(parsed.providerMessages)
        ? parsed.providerMessages
        : []
    };
  }

  snapshot() {
    return structuredClone(this.data);
  }

  replace(nextData) {
    this.data = {
      records: Array.isArray(nextData?.records) ? nextData.records : [],
      twitchOAuthStates: Array.isArray(nextData?.twitchOAuthStates)
        ? nextData.twitchOAuthStates
        : [],
      deliveryAttempts: Array.isArray(nextData?.deliveryAttempts)
        ? nextData.deliveryAttempts
        : [],
      tokenRefreshAttempts: Array.isArray(nextData?.tokenRefreshAttempts)
        ? nextData.tokenRefreshAttempts
        : [],
      providerMessages: Array.isArray(nextData?.providerMessages)
        ? nextData.providerMessages
        : []
    };
    this.save();
  }

  save() {
    if (!this.filePath) return;

    const dir = path.dirname(this.filePath);
    fs.mkdirSync(dir, { recursive: true });
    const tempPath = `${this.filePath}.tmp`;
    const payload = createEncryptedSnapshot({
      data: this.data,
      key: this.encryptionKey
    });
    fs.writeFileSync(tempPath, JSON.stringify(payload, null, 2));
    fs.renameSync(tempPath, this.filePath);
  }

  diagnostics() {
    return {
      type: "local_json",
      encrypted: this.encrypted
    };
  }
}
