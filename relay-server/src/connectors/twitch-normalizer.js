import crypto from "crypto";

function makeIds(metadata = {}) {
  const providerMessageId = metadata.message_id ?? crypto.randomUUID();
  return {
    providerMessageId,
    correlationId: `twitch:${providerMessageId}`
  };
}

function displayName(event = {}, ...keys) {
  for (const key of keys) {
    if (typeof event[key] === "string" && event[key].trim()) {
      return event[key];
    }
  }
  return "Unknown";
}

function numberOrNull(value) {
  if (typeof value === "number") return Number.isNaN(value) ? null : value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function baseAlert(metadata, event, type) {
  const { providerMessageId, correlationId } = makeIds(metadata);
  return {
    correlationId,
    providerMessageId,
    alert_id: providerMessageId,
    type,
    username: "Unknown",
    message: null,
    amount: null,
    formatted_amount: null,
    timestamp: new Date().toISOString(),
    source: "twitch_native"
  };
}

export function normalizeTwitchNotification(metadata, event) {
  if (!metadata || !event || typeof event !== "object") return null;

  const subscriptionType = metadata.subscription_type;

  if (subscriptionType === "channel.follow") {
    return {
      ...baseAlert(metadata, event, "follow"),
      username: displayName(event, "user_name", "user_login"),
      timestamp: event.followed_at ?? new Date().toISOString()
    };
  }

  if (subscriptionType === "channel.subscribe") {
    return {
      ...baseAlert(metadata, event, "subscription"),
      username: displayName(event, "user_name", "user_login")
    };
  }

  if (subscriptionType === "channel.subscription.gift") {
    const total = numberOrNull(event.total);
    return {
      ...baseAlert(metadata, event, "subscription"),
      username: event.is_anonymous
        ? "Anonymous"
        : displayName(event, "user_name", "user_login"),
      message: total ? `Gifted ${total} subscriptions` : "Gifted subscriptions",
      amount: total,
      formatted_amount: total ? `${total} gift subs` : null
    };
  }

  if (subscriptionType === "channel.subscription.message") {
    const cumulativeMonths = numberOrNull(event.cumulative_months);
    return {
      ...baseAlert(metadata, event, "subscription"),
      username: displayName(event, "user_name", "user_login"),
      message: event.message?.text ?? null,
      amount: cumulativeMonths,
      formatted_amount: cumulativeMonths ? `${cumulativeMonths} months` : null
    };
  }

  if (subscriptionType === "channel.cheer") {
    const bits = numberOrNull(event.bits);
    return {
      ...baseAlert(metadata, event, "bits"),
      username: displayName(event, "user_name", "user_login"),
      message: event.message ?? null,
      amount: bits,
      formatted_amount: bits ? `${bits} bits` : null
    };
  }

  if (subscriptionType === "channel.raid") {
    const viewers = numberOrNull(event.viewers);
    return {
      ...baseAlert(metadata, event, "raid"),
      username: displayName(
        event,
        "from_broadcaster_user_name",
        "from_broadcaster_user_login"
      ),
      amount: viewers,
      formatted_amount: viewers ? `${viewers} viewers` : null
    };
  }

  if (subscriptionType === "channel.channel_points_custom_reward_redemption.add") {
    return {
      ...baseAlert(metadata, event, "channel_points"),
      username: displayName(event, "user_name", "user_login"),
      message: event.user_input ?? event.reward?.title ?? null
    };
  }

  return null;
}
