import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";

const DEFAULT_BASE_URL = "http://localhost:3000";

export function normalizeBaseUrl(baseUrl = DEFAULT_BASE_URL) {
  return baseUrl.replace(/\/+$/, "");
}

export function buildProofAlert({
  now = new Date(),
  correlationId = null,
  providerMessageId = null
} = {}) {
  const timestamp = now instanceof Date ? now.toISOString() : new Date(now).toISOString();
  const id = randomUUID();
  const proofCorrelationId = correlationId ?? `proof:${id}`;
  const proofProviderMessageId = providerMessageId ?? `proof-${id}`;

  return {
    correlationId: proofCorrelationId,
    providerMessageId: proofProviderMessageId,
    alert_id: proofProviderMessageId,
    type: "follow",
    username: "RelayProof",
    message: "MVP proof alert from relay server",
    amount: null,
    formatted_amount: null,
    sound_url: null,
    timestamp,
    source: "twitch_native"
  };
}

async function requestJson({ fetchImpl, url, options = {} }) {
  const response = await fetchImpl(url, options);
  const text = await response.text();
  let body = null;

  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { raw: text };
    }
  }

  return {
    status: response.status,
    ok: response.ok,
    body
  };
}

function readinessSummary(readiness) {
  if (!readiness) return "Unknown";
  if (readiness.configured === true) return "Configured";
  if (Array.isArray(readiness.missing) && readiness.missing.length > 0) {
    return `Missing ${readiness.missing.join(", ")}`;
  }
  return "Incomplete";
}

function userSummary(diagnostics, userId) {
  const users = Array.isArray(diagnostics?.users) ? diagnostics.users : [];
  const user = users.find((candidate) => candidate.userId === userId);

  if (!user) {
    return {
      registered: false,
      hasDeviceToken: false,
      services: [],
      twitch: null
    };
  }

    return {
      registered: true,
      hasDeviceToken: Boolean(user.hasDeviceToken),
      deviceTokenFingerprint: user.deviceTokenFingerprint ?? null,
      deviceTokenLength: user.deviceTokenLength ?? 0,
      services: user.services ?? [],
      twitch: user.twitch ? {
        broadcasterId: user.twitch.broadcasterId,
        login: user.twitch.login,
      hasAccessToken: Boolean(user.twitch.hasAccessToken),
      hasRefreshToken: Boolean(user.twitch.hasRefreshToken),
      expiresAt: user.twitch.expiresAt
    } : null
  };
}

function findDeliveryAttempt({ diagnostics, attemptLookup, correlationId }) {
  const exactAttempts = Array.isArray(attemptLookup?.attempts) ? attemptLookup.attempts : [];
  const recentAttempts = Array.isArray(diagnostics?.recentDeliveryAttempts)
    ? diagnostics.recentDeliveryAttempts
    : [];
  const attempts = [...exactAttempts, ...recentAttempts];

  return attempts.findLast?.((attempt) => attempt.correlationId === correlationId)
    ?? attempts.slice().reverse().find((attempt) => attempt.correlationId === correlationId)
    ?? null;
}

function connectorSummary(diagnostics) {
  const connectors = Array.isArray(diagnostics?.connectors) ? diagnostics.connectors : [];
  return connectors.map((connector) => ({
    key: connector.key,
    service: connector.service,
    status: connector.status,
    sessionStatus: connector.sessionStatus,
    keepaliveStale: connector.keepaliveStale,
    subscriptionResults: connector.subscriptionResults
  }));
}

export function buildProofSummary({
  baseUrl,
  userId,
  alert,
  health,
  ready = null,
  diagnosticsBefore,
  alertResponse,
  diagnosticsAfter,
  attemptLookup
}) {
  const beforeBody = diagnosticsBefore.body ?? {};
  const afterBody = diagnosticsAfter.body ?? {};
  const attemptLookupBody = attemptLookup?.body ?? {};
  const matchedAttempt = findDeliveryAttempt({
    diagnostics: afterBody,
    attemptLookup: attemptLookupBody,
    correlationId: alert.correlationId
  });
  const beforeUser = userSummary(beforeBody, userId);
  const afterUser = userSummary(afterBody, userId);
  const failures = [];

  if (health.status !== 200 || health.body?.ok !== true) {
    failures.push("Relay health check did not return ok.");
  }
  if (ready && (ready.status !== 200 || ready.body?.ok !== true)) {
    failures.push("Relay readiness check did not return ok.");
  }
  if (ready?.body?.user && ready.body.user.ok !== true) {
    failures.push("Relay user readiness check did not return ok.");
  }
  if (diagnosticsBefore.status !== 200 || beforeBody.ok !== true) {
    failures.push("Relay diagnostics before the alert did not return ok.");
  }
  if (!beforeUser.registered) {
    failures.push(`Relay user ${userId} is not registered.`);
  }
  if (beforeUser.registered && !beforeUser.hasDeviceToken) {
    failures.push(`Relay user ${userId} has no APNs device token.`);
  }
  if (beforeUser.hasDeviceToken && !beforeUser.deviceTokenFingerprint) {
    failures.push(`Relay user ${userId} diagnostics did not include a device-token fingerprint.`);
  }
  if (alertResponse.status !== 200 || alertResponse.body?.ok !== true) {
    failures.push("Relay alert send did not return ok.");
  }
  if (diagnosticsAfter.status !== 200 || afterBody.ok !== true) {
    failures.push("Relay diagnostics after the alert did not return ok.");
  }
  if (attemptLookup && (attemptLookup.status !== 200 || attemptLookupBody.ok !== true)) {
    failures.push("Relay exact attempt lookup did not return ok.");
  }
  if (!matchedAttempt) {
    failures.push(`No relay delivery attempt was found for ${alert.correlationId}.`);
  }
  if (matchedAttempt && matchedAttempt.status !== "sent") {
    failures.push(`Relay delivery attempt status was ${matchedAttempt.status}.`);
  }
  if (matchedAttempt && beforeUser.deviceTokenFingerprint) {
    if (!matchedAttempt.deviceTokenFingerprint) {
      failures.push("Relay delivery attempt did not include a device-token fingerprint.");
    } else if (matchedAttempt.deviceTokenFingerprint !== beforeUser.deviceTokenFingerprint) {
      failures.push("Relay delivery attempt used a different device-token fingerprint than the registered user.");
    }
  }

  return {
    passed: failures.length === 0,
    failures,
    baseUrl,
    userId,
    correlationId: alert.correlationId,
    providerMessageId: alert.providerMessageId,
    health: {
      status: health.status,
      ok: health.body?.ok === true,
      users: health.body?.users ?? null,
      apnsReadiness: readinessSummary(health.body?.readiness?.apns),
      twitchOAuthReadiness: readinessSummary(health.body?.readiness?.twitchOAuth)
    },
    ready: ready ? {
      status: ready.status,
      ok: ready.body?.ok === true,
      checks: ready.body?.checks ?? [],
      user: ready.body?.user ? {
        ok: ready.body.user.ok === true,
        checks: ready.body.user.checks ?? [],
        twitch: ready.body.user.twitch ?? null,
        connector: ready.body.user.connector ?? null
      } : null
    } : null,
    before: {
      status: diagnosticsBefore.status,
      user: beforeUser,
      apnsReadiness: readinessSummary(beforeBody.readiness?.apns),
      twitchOAuthReadiness: readinessSummary(beforeBody.readiness?.twitchOAuth),
      connectors: connectorSummary(beforeBody)
    },
    alertSend: {
      status: alertResponse.status,
      ok: alertResponse.body?.ok === true,
      attempt: alertResponse.body?.attempt ?? null,
      error: alertResponse.body?.error ?? null,
      result: alertResponse.body?.result ?? null
    },
    after: {
      status: diagnosticsAfter.status,
      user: afterUser,
      matchedAttempt,
      exactLookupStatus: attemptLookup?.status ?? null,
      exactLookupCount: Array.isArray(attemptLookupBody.attempts) ? attemptLookupBody.attempts.length : null,
      connectors: connectorSummary(afterBody)
    }
  };
}

export async function runProof({
  baseUrl = DEFAULT_BASE_URL,
  userId,
  fetchImpl = globalThis.fetch,
  now = new Date()
} = {}) {
  if (!userId) {
    throw new Error("Missing relay user ID.");
  }
  if (typeof fetchImpl !== "function") {
    throw new Error("A fetch implementation is required.");
  }

  const normalizedBaseUrl = normalizeBaseUrl(baseUrl);
  const alert = buildProofAlert({ now });

  const health = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/health`
  });
  const ready = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/ready?userId=${encodeURIComponent(userId)}`
  });
  const diagnosticsBefore = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/diagnostics`
  });
  const alertResponse = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/alert`,
    options: {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userId, alert })
    }
  });
  const diagnosticsAfter = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/diagnostics`
  });
  const attemptLookup = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/diagnostics/attempts?correlationId=${encodeURIComponent(alert.correlationId)}`
  });

  return buildProofSummary({
    baseUrl: normalizedBaseUrl,
    userId,
    alert,
    health,
    ready,
    diagnosticsBefore,
    alertResponse,
    diagnosticsAfter,
    attemptLookup
  });
}

async function runCli() {
  const summary = await runProof({
    baseUrl: process.env.RELAY_BASE_URL ?? DEFAULT_BASE_URL,
    userId: process.env.RELAY_USER_ID
  });

  console.log(JSON.stringify(summary, null, 2));
  if (!summary.passed) {
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
