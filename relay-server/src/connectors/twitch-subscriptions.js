export const TWITCH_EVENTSUB_SUBSCRIPTIONS = [
  {
    type: "channel.follow",
    version: "2",
    requiredScopes: ["moderator:read:followers"],
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId,
      moderator_user_id: broadcasterId
    })
  },
  {
    type: "channel.subscribe",
    version: "1",
    requiredScopes: ["channel:read:subscriptions"],
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId
    })
  },
  {
    type: "channel.subscription.gift",
    version: "1",
    requiredScopes: ["channel:read:subscriptions"],
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId
    })
  },
  {
    type: "channel.subscription.message",
    version: "1",
    requiredScopes: ["channel:read:subscriptions"],
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId
    })
  },
  {
    type: "channel.cheer",
    version: "1",
    requiredScopes: ["bits:read"],
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId
    })
  },
  {
    type: "channel.raid",
    version: "1",
    requiredScopes: [],
    buildCondition: (broadcasterId) => ({
      to_broadcaster_user_id: broadcasterId
    })
  },
  {
    type: "channel.channel_points_custom_reward_redemption.add",
    version: "1",
    requiredScopes: ["channel:read:redemptions"],
    optionalForMvp: true,
    buildCondition: (broadcasterId) => ({
      broadcaster_user_id: broadcasterId
    })
  }
];

export function twitchRequiredScopes({ includeOptional = false } = {}) {
  const scopes = new Set();

  for (const subscription of TWITCH_EVENTSUB_SUBSCRIPTIONS) {
    if (subscription.optionalForMvp && !includeOptional) continue;
    for (const scope of subscription.requiredScopes) {
      scopes.add(scope);
    }
  }

  return Array.from(scopes).sort();
}
