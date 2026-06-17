import fs from "fs";
import apn from "@parse/node-apn";
import pino from "pino";
import {
  buildAlertText,
  buildApnsPayload,
  ensureAlertCorrelation,
  summarizeApnsResponse
} from "./apns-payload.js";

const logger = pino({
  transport: {
    target: "pino-pretty",
    options: { colorize: true }
  }
});

let provider = null;

function loadSigningKey() {
  if (process.env.APNS_PRIVATE_KEY_PATH) {
    return fs.readFileSync(process.env.APNS_PRIVATE_KEY_PATH);
  }
  if (process.env.APNS_PRIVATE_KEY) {
    return process.env.APNS_PRIVATE_KEY;
  }
  return null;
}

export function apnsConfigDiagnostics(env = process.env) {
  const hasPrivateKey = Boolean(env.APNS_PRIVATE_KEY);
  const hasPrivateKeyPath = Boolean(env.APNS_PRIVATE_KEY_PATH);
  const missing = [];

  if (!env.APNS_KEY_ID) missing.push("APNS_KEY_ID");
  if (!env.APNS_TEAM_ID) missing.push("APNS_TEAM_ID");
  if (!env.APNS_BUNDLE_ID) missing.push("APNS_BUNDLE_ID");
  if (!hasPrivateKey && !hasPrivateKeyPath) {
    missing.push("APNS_PRIVATE_KEY or APNS_PRIVATE_KEY_PATH");
  }

  return {
    configured: missing.length === 0,
    production: env.APNS_PRODUCTION === "true",
    hasKeyId: Boolean(env.APNS_KEY_ID),
    hasTeamId: Boolean(env.APNS_TEAM_ID),
    hasBundleId: Boolean(env.APNS_BUNDLE_ID),
    hasPrivateKey,
    hasPrivateKeyPath,
    missing
  };
}

function getProvider() {
  if (provider) return provider;

  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const signingKey = loadSigningKey();

  if (!keyId || !teamId || !signingKey) {
    logger.warn("APNs credentials missing. Push sending disabled.");
    return null;
  }

  provider = new apn.Provider({
    token: { key: signingKey, keyId, teamId },
    production: process.env.APNS_PRODUCTION === "true"
  });

  return provider;
}

export async function sendAlertPush({ deviceToken, alert }) {
  const correlatedAlert = ensureAlertCorrelation(alert);
  const apnProvider = getProvider();
  if (!apnProvider) {
    return {
      ok: false,
      error: "APNS_NOT_CONFIGURED",
      correlationId: correlatedAlert.correlationId,
      providerMessageId: correlatedAlert.providerMessageId
    };
  }

  if (!process.env.APNS_BUNDLE_ID) {
    return {
      ok: false,
      error: "APNS_BUNDLE_ID_MISSING",
      correlationId: correlatedAlert.correlationId,
      providerMessageId: correlatedAlert.providerMessageId
    };
  }

  const notification = new apn.Notification();
  notification.topic = process.env.APNS_BUNDLE_ID;
  notification.payload = buildApnsPayload(correlatedAlert);

  const { title, body } = buildAlertText(correlatedAlert);
  notification.alert = { title, body };
  notification.sound = "default";
  notification.mutableContent = 1;
  notification.contentAvailable = 1;

  try {
    const response = await apnProvider.send(notification, deviceToken);
    const summary = summarizeApnsResponse(response);
    return {
      ok: summary.failed === 0,
      response,
      summary,
      apnsIds: summary.apnsIds,
      correlationId: correlatedAlert.correlationId,
      providerMessageId: correlatedAlert.providerMessageId
    };
  } catch (error) {
    logger.error(`APNs send failed: ${error.message}`);
    return {
      ok: false,
      error: "APNS_SEND_FAILED",
      correlationId: correlatedAlert.correlationId,
      providerMessageId: correlatedAlert.providerMessageId
    };
  }
}
