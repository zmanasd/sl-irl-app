import test from "node:test";
import assert from "node:assert/strict";
import { normalizeTwitchNotification } from "../src/connectors/twitch-normalizer.js";
import {
  TWITCH_EVENTSUB_SUBSCRIPTIONS,
  twitchRequiredScopes
} from "../src/connectors/twitch-subscriptions.js";

function metadata(subscriptionType, messageId = `${subscriptionType}:message`) {
  return {
    message_id: messageId,
    subscription_type: subscriptionType
  };
}

test("defines Twitch MVP subscription types and scopes", () => {
  const types = TWITCH_EVENTSUB_SUBSCRIPTIONS.map((subscription) => subscription.type);

  assert.ok(types.includes("channel.follow"));
  assert.ok(types.includes("channel.subscribe"));
  assert.ok(types.includes("channel.subscription.gift"));
  assert.ok(types.includes("channel.subscription.message"));
  assert.ok(types.includes("channel.cheer"));
  assert.ok(types.includes("channel.raid"));

  assert.deepEqual(twitchRequiredScopes(), [
    "bits:read",
    "channel:read:subscriptions",
    "moderator:read:followers"
  ]);
});

test("normalizes follow events", () => {
  const alert = normalizeTwitchNotification(metadata("channel.follow", "msg-follow"), {
    user_name: "NewViewer",
    followed_at: "2026-06-14T10:00:00Z"
  });

  assert.equal(alert.correlationId, "twitch:msg-follow");
  assert.equal(alert.providerMessageId, "msg-follow");
  assert.equal(alert.type, "follow");
  assert.equal(alert.username, "NewViewer");
  assert.equal(alert.timestamp, "2026-06-14T10:00:00Z");
});

test("normalizes subscription events", () => {
  const alert = normalizeTwitchNotification(metadata("channel.subscribe", "msg-sub"), {
    user_name: "SubFan"
  });

  assert.equal(alert.correlationId, "twitch:msg-sub");
  assert.equal(alert.type, "subscription");
  assert.equal(alert.username, "SubFan");
});

test("normalizes gift subscription events", () => {
  const alert = normalizeTwitchNotification(
    metadata("channel.subscription.gift", "msg-gift"),
    {
      user_name: "GenerousViewer",
      total: 5
    }
  );

  assert.equal(alert.type, "subscription");
  assert.equal(alert.username, "GenerousViewer");
  assert.equal(alert.amount, 5);
  assert.equal(alert.formatted_amount, "5 gift subs");
});

test("normalizes resubscription message events", () => {
  const alert = normalizeTwitchNotification(
    metadata("channel.subscription.message", "msg-resub"),
    {
      user_name: "ReturningSub",
      cumulative_months: 12,
      message: { text: "One year!" }
    }
  );

  assert.equal(alert.type, "subscription");
  assert.equal(alert.username, "ReturningSub");
  assert.equal(alert.amount, 12);
  assert.equal(alert.formatted_amount, "12 months");
  assert.equal(alert.message, "One year!");
});

test("normalizes cheer events", () => {
  const alert = normalizeTwitchNotification(metadata("channel.cheer", "msg-cheer"), {
    user_name: "BitsUser",
    bits: 500,
    message: "Keep going"
  });

  assert.equal(alert.type, "bits");
  assert.equal(alert.username, "BitsUser");
  assert.equal(alert.amount, 500);
  assert.equal(alert.formatted_amount, "500 bits");
  assert.equal(alert.message, "Keep going");
});

test("normalizes raid events", () => {
  const alert = normalizeTwitchNotification(metadata("channel.raid", "msg-raid"), {
    from_broadcaster_user_name: "RaidLeader",
    viewers: 42
  });

  assert.equal(alert.type, "raid");
  assert.equal(alert.username, "RaidLeader");
  assert.equal(alert.amount, 42);
  assert.equal(alert.formatted_amount, "42 viewers");
});

test("normalizes optional channel point redemption events", () => {
  const alert = normalizeTwitchNotification(
    metadata("channel.channel_points_custom_reward_redemption.add", "msg-points"),
    {
      user_name: "Redeemer",
      user_input: "Hydrate",
      reward: { title: "Hydration break" }
    }
  );

  assert.equal(alert.type, "channel_points");
  assert.equal(alert.username, "Redeemer");
  assert.equal(alert.message, "Hydrate");
});

test("returns null for unsupported notification types", () => {
  const alert = normalizeTwitchNotification(metadata("unknown.type"), {
    user_name: "Mystery"
  });

  assert.equal(alert, null);
});
