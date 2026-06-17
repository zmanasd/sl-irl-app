import test from "node:test";
import assert from "node:assert/strict";
import {
  buildAlertText,
  buildApnsPayload,
  ensureAlertCorrelation,
  summarizeApnsResponse
} from "../src/apns-payload.js";
import { apnsConfigDiagnostics } from "../src/apns.js";

test("ensures alert correlation from provider message id", () => {
  const alert = ensureAlertCorrelation({
    providerMessageId: "msg-1",
    source: "twitch_native",
    type: "follow"
  });

  assert.equal(alert.correlationId, "twitch_native:msg-1");
  assert.equal(alert.providerMessageId, "msg-1");
});

test("builds APNs payload with top-level correlation fields", () => {
  const payload = buildApnsPayload({
    correlationId: "twitch:msg-1",
    providerMessageId: "msg-1",
    source: "twitch_native",
    type: "follow",
    username: "Viewer"
  });

  assert.equal(payload.correlationId, "twitch:msg-1");
  assert.equal(payload.providerMessageId, "msg-1");
  assert.equal(payload.alert.correlationId, "twitch:msg-1");
  assert.equal(payload.alert.username, "Viewer");
});

test("builds human alert text", () => {
  const text = buildAlertText({
    username: "Viewer",
    type: "bits",
    formatted_amount: "500 bits"
  });

  assert.equal(text.title, "IRL Alert");
  assert.equal(text.body, "Viewer triggered a bits 500 bits.");
});

test("summarizes APNs response without exposing device tokens", () => {
  const summary = summarizeApnsResponse({
    sent: [
      {
        device: "secret-device-token",
        response: { headers: { "apns-id": "apns-1" } }
      }
    ],
    failed: [
      {
        device: "secret-device-token",
        response: { reason: "BadDeviceToken" }
      }
    ]
  });

  assert.deepEqual(summary, {
    sent: 1,
    failed: 1,
    apnsIds: ["apns-1"],
    failedReasons: ["BadDeviceToken"]
  });
  assert.equal(JSON.stringify(summary).includes("secret-device-token"), false);
});

test("reports APNs config readiness without exposing secrets", () => {
  const diagnostics = apnsConfigDiagnostics({
    APNS_KEY_ID: "key-id",
    APNS_TEAM_ID: "team-id",
    APNS_BUNDLE_ID: "com.example.app",
    APNS_PRIVATE_KEY: "secret-private-key",
    APNS_PRODUCTION: "true"
  });

  assert.equal(diagnostics.configured, true);
  assert.equal(diagnostics.production, true);
  assert.equal(diagnostics.hasPrivateKey, true);
  assert.equal(diagnostics.missing.length, 0);
  assert.equal(JSON.stringify(diagnostics).includes("secret-private-key"), false);
});

test("reports missing APNs config fields", () => {
  const diagnostics = apnsConfigDiagnostics({});

  assert.equal(diagnostics.configured, false);
  assert.ok(diagnostics.missing.includes("APNS_KEY_ID"));
  assert.ok(diagnostics.missing.includes("APNS_TEAM_ID"));
  assert.ok(diagnostics.missing.includes("APNS_BUNDLE_ID"));
  assert.ok(diagnostics.missing.includes("APNS_PRIVATE_KEY or APNS_PRIVATE_KEY_PATH"));
});
