import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

const SECRET_VERSION = 1;
const SECRET_ALGORITHM = "aes-256-gcm";

export function decodeSecretKey(key, name = "secret encryption key") {
  if (!key) return null;

  for (const encoding of ["base64", "hex"]) {
    const decoded = Buffer.from(key, encoding);
    if (decoded.length === 32) return decoded;
  }

  throw new Error(`${name} must decode to 32 bytes as base64 or hex.`);
}

export function isSecretBox(value) {
  return Boolean(
    value
    && typeof value === "object"
    && value.encrypted === true
    && value.purpose === "relay_secret"
  );
}

export function encryptSecret(value, {
  key,
  keyId = "default",
  iv = randomBytes(12)
} = {}) {
  if (value == null) return value;
  const decodedKey = decodeSecretKey(key, "RELAY_TOKEN_ENCRYPTION_KEY");
  if (!decodedKey) return value;

  const cipher = createCipheriv(SECRET_ALGORITHM, decodedKey, iv);
  const plaintext = Buffer.from(String(value), "utf8");
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);

  return {
    encrypted: true,
    purpose: "relay_secret",
    version: SECRET_VERSION,
    algorithm: SECRET_ALGORITHM,
    keyId,
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    data: ciphertext.toString("base64")
  };
}

export function decryptSecret(value, { key } = {}) {
  if (!isSecretBox(value)) return value;

  const decodedKey = decodeSecretKey(key, "RELAY_TOKEN_ENCRYPTION_KEY");
  if (!decodedKey) {
    throw new Error("RELAY_TOKEN_ENCRYPTION_KEY is required to read encrypted relay secrets.");
  }
  if (value.version !== SECRET_VERSION || value.algorithm !== SECRET_ALGORITHM) {
    throw new Error("Unsupported encrypted relay secret format.");
  }

  const decipher = createDecipheriv(
    SECRET_ALGORITHM,
    decodedKey,
    Buffer.from(value.iv, "base64")
  );
  decipher.setAuthTag(Buffer.from(value.tag, "base64"));

  return Buffer.concat([
    decipher.update(Buffer.from(value.data, "base64")),
    decipher.final()
  ]).toString("utf8");
}

export function secretEncryptionDiagnostics({
  key,
  keyId = null
} = {}) {
  return {
    configured: Boolean(key),
    keyId: key ? keyId ?? "default" : null,
    algorithm: key ? SECRET_ALGORITHM : null,
    missing: key ? [] : ["RELAY_TOKEN_ENCRYPTION_KEY"]
  };
}
