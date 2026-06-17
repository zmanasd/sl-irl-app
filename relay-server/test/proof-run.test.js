import test from "node:test";
import assert from "node:assert/strict";
import {
  buildProofAlert,
  normalizeBaseUrl,
  runProof
} from "../scripts/proof-run.js";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

function diagnosticsPayload({
  userId,
  correlationId = null,
  attemptFingerprint = "abc123def456"
} = {}) {
  const recentDeliveryAttempts = correlationId ? [{
    userId,
    correlationId,
    providerMessageId: "proof-provider",
    source: "twitch_native",
    type: "follow",
    status: "sent",
    deviceTokenLength: 64,
    deviceTokenFingerprint: attemptFingerprint,
    apnsIds: ["apns-proof"],
    apnsSent: 1,
    apnsFailed: 0,
    error: null,
    createdAt: "2026-06-15T10:00:00.000Z"
  }] : [];

  return {
    ok: true,
    users: [{
      userId,
      hasDeviceToken: true,
      deviceTokenLength: 64,
      deviceTokenFingerprint: "abc123def456",
      services: ["twitch_native"],
      twitch: {
        broadcasterId: "1234",
        login: "streamer",
        hasAccessToken: true,
        hasRefreshToken: true,
        expiresAt: "2026-06-15T11:00:00.000Z"
      }
    }],
    readiness: {
      apns: { configured: true, missing: [] },
      twitchOAuth: { configured: true, missing: [] }
    },
    connectors: [{
      key: "twitch_native:user-1",
      service: "twitch_native",
      status: "connected",
      sessionStatus: "ready",
      keepaliveStale: false,
      subscriptionResults: []
    }],
    recentDeliveryAttempts
  };
}

test("buildProofAlert creates a normalized Twitch proof alert", () => {
  const alert = buildProofAlert({
    now: "2026-06-15T10:00:00.000Z",
    correlationId: "proof:fixed",
    providerMessageId: "proof-provider"
  });

  assert.equal(alert.correlationId, "proof:fixed");
  assert.equal(alert.providerMessageId, "proof-provider");
  assert.equal(alert.alert_id, "proof-provider");
  assert.equal(alert.source, "twitch_native");
  assert.equal(alert.timestamp, "2026-06-15T10:00:00.000Z");
});

test("runProof captures health, diagnostics, alert send, and matched delivery attempt", async () => {
  const calls = [];

  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });

    if (url.endsWith("/health")) {
      return jsonResponse({
        ok: true,
        users: 1,
        readiness: {
          apns: { configured: true, missing: [] },
          twitchOAuth: { configured: true, missing: [] }
        }
      });
    }

    if (new URL(url).pathname === "/ready") {
      assert.equal(new URL(url).searchParams.get("userId"), "user-1");
      return jsonResponse({
        ok: true,
        checks: [],
        user: { ok: true, checks: [], twitch: null, connector: null }
      });
    }

    if (url.endsWith("/diagnostics") && calls.filter((call) => call.url.endsWith("/diagnostics")).length === 1) {
      return jsonResponse(diagnosticsPayload({ userId: "user-1" }));
    }

    if (url.endsWith("/alert")) {
      const payload = JSON.parse(options.body);
      assert.equal(payload.userId, "user-1");
      assert.equal(payload.alert.source, "twitch_native");
      assert.equal(payload.alert.correlationId.startsWith("proof:"), true);

      return jsonResponse({
        ok: true,
        attempt: {
          userId: "user-1",
          correlationId: payload.alert.correlationId,
          providerMessageId: payload.alert.providerMessageId,
          source: "twitch_native",
          type: "follow",
          status: "sent",
          deviceTokenLength: 64,
          deviceTokenFingerprint: "abc123def456",
          apnsIds: ["apns-proof"],
          apnsSent: 1,
          apnsFailed: 0,
          error: null,
          createdAt: "2026-06-15T10:00:00.000Z"
        },
        result: { ok: true, apnsIds: ["apns-proof"], summary: { sent: 1, failed: 0 } }
      });
    }

    if (url.endsWith("/diagnostics")) {
      const alertCall = calls.find((call) => call.url.endsWith("/alert"));
      const correlationId = JSON.parse(alertCall.options.body).alert.correlationId;
      return jsonResponse(diagnosticsPayload({ userId: "user-1", correlationId }));
    }

    if (url.includes("/diagnostics/attempts")) {
      const correlationId = new URL(url).searchParams.get("correlationId");
      return jsonResponse({
        ok: true,
        correlationId,
        providerMessageId: null,
        userId: null,
        attempts: diagnosticsPayload({ userId: "user-1", correlationId }).recentDeliveryAttempts
      });
    }

    throw new Error(`Unexpected URL ${url}`);
  };

  const summary = await runProof({
    baseUrl: "http://relay.example.test/",
    userId: "user-1",
    fetchImpl,
    now: "2026-06-15T10:00:00.000Z"
  });

  assert.equal(summary.passed, true);
  assert.deepEqual(summary.failures, []);
  assert.equal(summary.baseUrl, "http://relay.example.test");
  assert.equal(summary.health.apnsReadiness, "Configured");
  assert.equal(summary.ready.ok, true);
  assert.equal(summary.ready.user.ok, true);
  assert.equal(summary.before.user.registered, true);
  assert.equal(summary.before.user.deviceTokenFingerprint, "abc123def456");
  assert.equal(summary.alertSend.attempt.status, "sent");
  assert.equal(summary.after.matchedAttempt.deviceTokenFingerprint, "abc123def456");
  assert.equal(summary.after.matchedAttempt.apnsIds[0], "apns-proof");
  assert.equal(summary.after.exactLookupCount, 1);
  assert.deepEqual(calls.map((call) => new URL(call.url).pathname), [
    "/health",
    "/ready",
    "/diagnostics",
    "/alert",
    "/diagnostics",
    "/diagnostics/attempts"
  ]);
});

test("runProof fails when delivery attempt token fingerprint differs from registered user", async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });

    if (url.endsWith("/health")) {
      return jsonResponse({ ok: true, users: 1, readiness: {} });
    }
    if (new URL(url).pathname === "/ready") {
      return jsonResponse({
        ok: true,
        checks: [],
        user: { ok: true, checks: [], twitch: null, connector: null }
      });
    }
    if (url.endsWith("/diagnostics") && calls.filter((call) => call.url.endsWith("/diagnostics")).length === 1) {
      return jsonResponse(diagnosticsPayload({ userId: "user-1" }));
    }
    if (url.endsWith("/alert")) {
      const payload = JSON.parse(options.body);
      return jsonResponse({
        ok: true,
        attempt: {
          userId: "user-1",
          correlationId: payload.alert.correlationId,
          providerMessageId: payload.alert.providerMessageId,
          source: "twitch_native",
          type: "follow",
          status: "sent",
          deviceTokenLength: 64,
          deviceTokenFingerprint: "wrongtoken123",
          apnsIds: ["apns-proof"],
          apnsSent: 1,
          apnsFailed: 0,
          error: null,
          createdAt: "2026-06-15T10:00:00.000Z"
        }
      });
    }
    if (url.endsWith("/diagnostics")) {
      const alertCall = calls.find((call) => call.url.endsWith("/alert"));
      const correlationId = JSON.parse(alertCall.options.body).alert.correlationId;
      return jsonResponse(diagnosticsPayload({
        userId: "user-1",
        correlationId,
        attemptFingerprint: "wrongtoken123"
      }));
    }
    if (url.includes("/diagnostics/attempts")) {
      const correlationId = new URL(url).searchParams.get("correlationId");
      return jsonResponse({
        ok: true,
        correlationId,
        attempts: diagnosticsPayload({
          userId: "user-1",
          correlationId,
          attemptFingerprint: "wrongtoken123"
        }).recentDeliveryAttempts
      });
    }
    throw new Error(`Unexpected URL ${url}`);
  };

  const summary = await runProof({
    userId: "user-1",
    fetchImpl,
    now: "2026-06-15T10:00:00.000Z"
  });

  assert.equal(summary.passed, false);
  assert.equal(
    summary.failures.includes("Relay delivery attempt used a different device-token fingerprint than the registered user."),
    true
  );
});

test("runProof fails clearly when relay user is not registered", async () => {
  const fetchImpl = async (url) => {
    if (url.endsWith("/health")) {
      return jsonResponse({ ok: true, users: 0, readiness: {} });
    }
    if (new URL(url).pathname === "/ready") {
      return jsonResponse({
        ok: false,
        checks: [],
        user: {
          ok: false,
          checks: [{ name: "registered_user", ok: false, missing: ["user registration"] }]
        }
      }, 503);
    }
    if (url.endsWith("/diagnostics")) {
      return jsonResponse({ ok: true, users: [], recentDeliveryAttempts: [], connectors: [] });
    }
    if (url.includes("/diagnostics/attempts")) {
      return jsonResponse({ ok: true, attempts: [] });
    }
    if (url.endsWith("/alert")) {
      return jsonResponse({ error: "user not registered" }, 404);
    }
    throw new Error(`Unexpected URL ${url}`);
  };

  const summary = await runProof({
    userId: "missing-user",
    fetchImpl,
    now: "2026-06-15T10:00:00.000Z"
  });

  assert.equal(summary.passed, false);
  assert.equal(summary.failures.includes("Relay user missing-user is not registered."), true);
  assert.equal(summary.failures.includes("Relay alert send did not return ok."), true);
});

test("runProof fails clearly when relay readiness check fails", async () => {
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith("/health")) {
      return jsonResponse({ ok: true, users: 1, readiness: {} });
    }
    if (new URL(url).pathname === "/ready") {
      return jsonResponse({
        ok: false,
        checks: [{ name: "apns", ok: false, missing: ["APNS_KEY_ID"] }],
        user: { ok: true, checks: [] }
      }, 503);
    }
    if (url.endsWith("/diagnostics")) {
      return jsonResponse(diagnosticsPayload({ userId: "user-1" }));
    }
    if (url.endsWith("/alert")) {
      const payload = JSON.parse(options.body);
      return jsonResponse({
        ok: true,
        attempt: {
          userId: "user-1",
          correlationId: payload.alert.correlationId,
          providerMessageId: payload.alert.providerMessageId,
          source: "twitch_native",
          type: "follow",
          status: "sent",
          deviceTokenLength: 64,
          deviceTokenFingerprint: "abc123def456",
          apnsIds: ["apns-proof"],
          apnsSent: 1,
          apnsFailed: 0,
          error: null,
          createdAt: "2026-06-15T10:00:00.000Z"
        }
      });
    }
    if (url.includes("/diagnostics/attempts")) {
      return jsonResponse({ ok: true, attempts: [] });
    }
    throw new Error(`Unexpected URL ${url}`);
  };

  const summary = await runProof({
    userId: "user-1",
    fetchImpl,
    now: "2026-06-15T10:00:00.000Z"
  });

  assert.equal(summary.passed, false);
  assert.equal(summary.ready.status, 503);
  assert.equal(summary.failures.includes("Relay readiness check did not return ok."), true);
});

test("normalizeBaseUrl removes trailing slashes", () => {
  assert.equal(normalizeBaseUrl("http://localhost:3000///"), "http://localhost:3000");
});
