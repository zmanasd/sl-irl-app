import test from "node:test";
import assert from "node:assert/strict";
import {
  buildManualTestAlert,
  sendManualTestAlert
} from "../scripts/send-test-alert.js";

test("buildManualTestAlert uses one traceable identity across alert IDs", () => {
  const alert = buildManualTestAlert({
    now: "2026-06-17T10:00:00.000Z",
    correlationId: "manual-test:fixed"
  });

  assert.equal(alert.correlationId, "manual-test:fixed");
  assert.equal(alert.providerMessageId, "manual-test:fixed");
  assert.equal(alert.alert_id, "manual-test:fixed");
  assert.equal(alert.source, "twitch_native");
  assert.equal(alert.timestamp, "2026-06-17T10:00:00.000Z");
});

test("sendManualTestAlert posts the correlated alert to the relay", async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  };

  const result = await sendManualTestAlert({
    fetchImpl,
    baseUrl: "https://relay.example.test",
    userId: "user-1",
    now: "2026-06-17T10:00:00.000Z"
  });

  const posted = JSON.parse(calls[0].options.body);
  assert.equal(result.status, 200);
  assert.equal(calls[0].url, "https://relay.example.test/alert");
  assert.equal(posted.userId, "user-1");
  assert.equal(posted.alert.correlationId, posted.alert.providerMessageId);
  assert.equal(posted.alert.correlationId, posted.alert.alert_id);
});
