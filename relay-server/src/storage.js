import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import fs from "fs";
import path from "path";

const ENCRYPTION_VERSION = 1;
const ENCRYPTION_ALGORITHM = "aes-256-gcm";
const DEFAULT_POSTGRES_STORE_KEY = "relay";

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
      providerMessages: [],
      appReceipts: [],
      operations: {}
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
        : [],
      appReceipts: Array.isArray(parsed.appReceipts)
        ? parsed.appReceipts
        : [],
      operations: parsed.operations && typeof parsed.operations === "object"
        ? parsed.operations
        : {}
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
        : [],
      appReceipts: Array.isArray(nextData?.appReceipts)
        ? nextData.appReceipts
        : [],
      operations: nextData?.operations && typeof nextData.operations === "object"
        ? nextData.operations
        : {}
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

export class PostgresSnapshotStore {
  constructor({
    pool,
    key = DEFAULT_POSTGRES_STORE_KEY,
    encryptionKey = process.env.RELAY_STORAGE_ENCRYPTION_KEY,
    data = null
  }) {
    this.pool = pool;
    this.key = key;
    this.encryptionKey = encryptionKey;
    this.encrypted = Boolean(encryptionKey);
    this.pendingWrite = null;
    this.data = normalizeSnapshot(data);
  }

  static async create({
    connectionString = process.env.DATABASE_URL,
    key = DEFAULT_POSTGRES_STORE_KEY,
    encryptionKey = process.env.RELAY_STORAGE_ENCRYPTION_KEY,
    ssl = process.env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : undefined
  } = {}) {
    if (!connectionString) {
      throw new Error("DATABASE_URL is required for Postgres storage.");
    }

    const { Pool } = await import("pg");
    const pool = new Pool({ connectionString, ssl });
    await ensurePostgresSchema(pool);

    const result = await pool.query(
      "select payload from relay_snapshots where key = $1",
      [key]
    );
    const payload = result.rows[0]?.payload ?? null;
    const data = payload
      ? readEncryptedSnapshot({ payload, key: encryptionKey })
      : null;

    return new PostgresSnapshotStore({
      pool,
      key,
      encryptionKey,
      data
    });
  }

  snapshot() {
    return structuredClone(this.data);
  }

  replace(nextData) {
    this.data = normalizeSnapshot(nextData);
    const payload = createEncryptedSnapshot({
      data: this.data,
      key: this.encryptionKey
    });

    this.pendingWrite = this.pool.query(
      `insert into relay_snapshots (key, payload, updated_at)
       values ($1, $2::jsonb, now())
       on conflict (key)
       do update set payload = excluded.payload, updated_at = excluded.updated_at`,
      [this.key, JSON.stringify(payload)]
    );

    return this.pendingWrite;
  }

  async flush() {
    if (this.pendingWrite) {
      await this.pendingWrite;
      this.pendingWrite = null;
    }
  }

  async close() {
    await this.flush();
    await this.pool.end();
  }

  diagnostics() {
    return {
      type: "postgres_snapshot",
      encrypted: this.encrypted,
      key: this.key
    };
  }
}

export async function createStoreFromEnv(env = process.env) {
  const driver = env.RELAY_STORAGE_DRIVER ?? (env.DATABASE_URL ? "postgres" : "local_json");

  if (driver === "postgres") {
    return PostgresSnapshotStore.create({
      connectionString: env.DATABASE_URL,
      key: env.RELAY_POSTGRES_SNAPSHOT_KEY ?? DEFAULT_POSTGRES_STORE_KEY,
      encryptionKey: env.RELAY_STORAGE_ENCRYPTION_KEY,
      ssl: env.DATABASE_SSL === "true" ? { rejectUnauthorized: false } : undefined
    });
  }

  if (driver !== "local_json") {
    throw new Error(`Unsupported RELAY_STORAGE_DRIVER: ${driver}`);
  }

  const dataPath = env.RELAY_DATA_PATH
    ?? path.resolve("relay-server/.data/relay-store.json");
  return new LocalJsonStore(dataPath, {
    encryptionKey: env.RELAY_STORAGE_ENCRYPTION_KEY
  });
}

async function ensurePostgresSchema(pool) {
  await pool.query(`
    create table if not exists relay_snapshots (
      key text primary key,
      payload jsonb not null,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `);
}

function normalizeSnapshot(snapshot) {
  return {
    records: Array.isArray(snapshot?.records) ? snapshot.records : [],
    twitchOAuthStates: Array.isArray(snapshot?.twitchOAuthStates)
      ? snapshot.twitchOAuthStates
      : [],
    deliveryAttempts: Array.isArray(snapshot?.deliveryAttempts)
      ? snapshot.deliveryAttempts
      : [],
    tokenRefreshAttempts: Array.isArray(snapshot?.tokenRefreshAttempts)
      ? snapshot.tokenRefreshAttempts
      : [],
    providerMessages: Array.isArray(snapshot?.providerMessages)
      ? snapshot.providerMessages
      : [],
    appReceipts: Array.isArray(snapshot?.appReceipts)
      ? snapshot.appReceipts
      : [],
    operations: snapshot?.operations && typeof snapshot.operations === "object"
      ? snapshot.operations
      : {}
  };
}
