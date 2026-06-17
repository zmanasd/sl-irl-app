import test from "node:test";
import assert from "node:assert/strict";
import { TwitchEventSubConnector } from "../src/connectors/twitch.js";

const logger = {
  info() {},
  warn() {},
  error() {}
};

function connector(overrides = {}) {
  return new TwitchEventSubConnector({
    userId: "user-1",
    token: "token",
    clientId: "client-id",
    logger,
    onAlert() {},
    ...overrides
  });
}

test("records session welcome diagnostics and subscription results", async () => {
  const c = connector();
  c.broadcasterId = "1234";
  const created = [];
  c.createSubscription = async ({ type }) => {
    created.push(type);
    c.subscriptionResults.set(type, {
      type,
      ok: true,
      status: 202,
      subscriptionId: `${type}:id`,
      updatedAt: "2026-06-14T00:00:00Z"
    });
  };

  await c.handleMessage(JSON.stringify({
    metadata: {
      message_type: "session_welcome",
      message_id: "welcome-1"
    },
    payload: {
      session: {
        id: "session-1",
        reconnect_url: "wss://reconnect.example",
        keepalive_timeout_seconds: 10
      }
    }
  }));

  const diagnostics = c.diagnostics(new Date("2026-06-14T00:00:05Z"));
  assert.equal(c.sessionId, "session-1");
  assert.equal(c.keepaliveTimeoutSeconds, 10);
  assert.equal(diagnostics.status, "session_ready");
  assert.equal(diagnostics.hasReconnectUrl, true);
  assert.equal(diagnostics.keepaliveStale, false);
  assert.ok(created.includes("channel.follow"));
  assert.ok(diagnostics.subscriptionResults.length > 0);
});

test("updates keepalive timestamp and detects stale keepalive", async () => {
  const c = connector();

  await c.handleMessage(JSON.stringify({
    metadata: {
      message_type: "session_welcome",
      message_id: "welcome-1"
    },
    payload: {
      session: {
        id: "session-1",
        keepalive_timeout_seconds: 10
      }
    }
  }));

  c.lastKeepaliveAt = "2026-06-14T00:00:00Z";

  assert.equal(c.isKeepaliveStale(new Date("2026-06-14T00:00:19Z")), false);
  assert.equal(c.isKeepaliveStale(new Date("2026-06-14T00:00:21Z")), true);
});

test("records failed subscription creation", async () => {
  const c = connector();
  c.fetch = async () => ({
    ok: false,
    status: 403,
    text: async () => "missing scope"
  });

  await c.createSubscription({
    type: "channel.follow",
    version: "2",
    condition: { broadcaster_user_id: "1234", moderator_user_id: "1234" },
    sessionId: "session-1"
  });

  const result = c.diagnostics().subscriptionResults[0];
  assert.equal(result.type, "channel.follow");
  assert.equal(result.ok, false);
  assert.equal(result.status, 403);
  assert.equal(result.error, "missing scope");
});

test("records successful subscription creation", async () => {
  const c = connector();
  c.fetch = async () => ({
    ok: true,
    status: 202,
    json: async () => ({ data: [{ id: "sub-1" }] })
  });

  await c.createSubscription({
    type: "channel.follow",
    version: "2",
    condition: { broadcaster_user_id: "1234", moderator_user_id: "1234" },
    sessionId: "session-1"
  });

  const result = c.diagnostics().subscriptionResults[0];
  assert.equal(result.type, "channel.follow");
  assert.equal(result.ok, true);
  assert.equal(result.status, 202);
  assert.equal(result.subscriptionId, "sub-1");
});
