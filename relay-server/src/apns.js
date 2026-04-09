import fs from "fs";
import apn from "@parse/node-apn";
import pino from "pino";

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

function buildAlertText(alert) {
  if (!alert) return { title: "IRL Alert", body: "New alert received." };
  const username = alert.username ?? "Someone";
  const type = alert.type ?? "alert";
  const amount = alert.formatted_amount ?? alert.formattedAmount ?? "";
  const suffix = amount ? ` ${amount}` : "";
  return {
    title: "IRL Alert",
    body: `${username} triggered a ${type}${suffix}.`
  };
}

export async function sendAlertPush({ deviceToken, alert }) {
  const apnProvider = getProvider();
  if (!apnProvider) {
    return { ok: false, error: "APNS_NOT_CONFIGURED" };
  }

  if (!process.env.APNS_BUNDLE_ID) {
    return { ok: false, error: "APNS_BUNDLE_ID_MISSING" };
  }

  const notification = new apn.Notification();
  notification.topic = process.env.APNS_BUNDLE_ID;
  notification.payload = { alert };

  const { title, body } = buildAlertText(alert);
  notification.alert = { title, body };
  notification.sound = "default";
  notification.mutableContent = 1;
  notification.contentAvailable = 1;

  try {
    const response = await apnProvider.send(notification, deviceToken);
    return { ok: true, response };
  } catch (error) {
    logger.error(`APNs send failed: ${error.message}`);
    return { ok: false, error: "APNS_SEND_FAILED" };
  }
}
