import crypto from "crypto";

export function ensureAlertCorrelation(alert = {}) {
  const providerMessageId = alert.providerMessageId
    ?? alert.provider_message_id
    ?? alert.alert_id
    ?? alert.id
    ?? null;
  const source = alert.source ?? "relay";
  const correlationId = alert.correlationId
    ?? alert.correlation_id
    ?? (providerMessageId ? `${source}:${providerMessageId}` : `relay:${crypto.randomUUID()}`);

  return {
    ...alert,
    correlationId,
    providerMessageId
  };
}

export function buildAlertText(alert) {
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

export function buildApnsPayload(alert) {
  const correlatedAlert = ensureAlertCorrelation(alert);
  return {
    alert: correlatedAlert,
    correlationId: correlatedAlert.correlationId,
    providerMessageId: correlatedAlert.providerMessageId
  };
}

export function summarizeApnsResponse(response) {
  const sent = Array.isArray(response?.sent) ? response.sent : [];
  const failed = Array.isArray(response?.failed) ? response.failed : [];
  const apnsIds = sent
    .map((item) => item?.response?.headers?.["apns-id"] ?? item?.response?.apnsId)
    .filter(Boolean);

  return {
    sent: sent.length,
    failed: failed.length,
    apnsIds,
    failedReasons: failed.map((item) => (
      item?.response?.reason
      ?? item?.error?.message
      ?? item?.status
      ?? "unknown"
    ))
  };
}
