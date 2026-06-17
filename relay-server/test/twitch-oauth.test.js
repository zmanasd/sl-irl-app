import test from "node:test";
import assert from "node:assert/strict";
import {
  createTwitchOAuthStart,
  exchangeTwitchCode,
  fetchTwitchUser,
  refreshTwitchToken,
  twitchOAuthConfigFromEnv,
  twitchOAuthDiagnostics
} from "../src/twitch-oauth.js";

const config = {
  clientId: "client-id",
  clientSecret: "client-secret",
  redirectUri: "http://localhost:3000/auth/twitch/callback",
  scopes: ["bits:read", "channel:read:subscriptions"]
};

test("builds Twitch OAuth config from environment", () => {
  const result = twitchOAuthConfigFromEnv({
    TWITCH_CLIENT_ID: "client-id",
    TWITCH_CLIENT_SECRET: "client-secret",
    TWITCH_REDIRECT_URI: "http://localhost/callback"
  });

  assert.equal(result.clientId, "client-id");
  assert.equal(result.clientSecret, "client-secret");
  assert.equal(result.redirectUri, "http://localhost/callback");
  assert.ok(result.scopes.includes("bits:read"));
});

test("reports Twitch OAuth config readiness without exposing secrets", () => {
  const diagnostics = twitchOAuthDiagnostics({
    TWITCH_CLIENT_ID: "client-id",
    TWITCH_CLIENT_SECRET: "secret-value",
    TWITCH_REDIRECT_URI: "http://localhost/callback"
  });

  assert.equal(diagnostics.configured, true);
  assert.equal(diagnostics.hasClientId, true);
  assert.equal(diagnostics.hasClientSecret, true);
  assert.equal(diagnostics.hasRedirectUri, true);
  assert.ok(diagnostics.scopes.includes("bits:read"));
  assert.equal(JSON.stringify(diagnostics).includes("secret-value"), false);
});

test("reports missing Twitch OAuth config fields", () => {
  const diagnostics = twitchOAuthDiagnostics({});

  assert.equal(diagnostics.configured, false);
  assert.deepEqual(diagnostics.missing, [
    "TWITCH_CLIENT_ID",
    "TWITCH_CLIENT_SECRET",
    "TWITCH_REDIRECT_URI"
  ]);
});

test("creates Twitch OAuth URL and pending state", () => {
  const result = createTwitchOAuthStart({
    userId: "user-1",
    config,
    now: new Date("2026-06-14T00:00:00Z")
  });
  const url = new URL(result.authUrl);

  assert.equal(url.origin + url.pathname, "https://id.twitch.tv/oauth2/authorize");
  assert.equal(url.searchParams.get("client_id"), "client-id");
  assert.equal(url.searchParams.get("redirect_uri"), config.redirectUri);
  assert.equal(url.searchParams.get("response_type"), "code");
  assert.equal(url.searchParams.get("scope"), config.scopes.join(" "));
  assert.equal(url.searchParams.get("state"), result.state);
  assert.equal(result.pendingState.userId, "user-1");
  assert.equal(result.pendingState.createdAt, "2026-06-14T00:00:00.000Z");
});

test("exchanges Twitch OAuth code", async () => {
  const calls = [];
  const tokenPayload = {
    access_token: "access-token",
    refresh_token: "refresh-token",
    expires_in: 3600
  };

  const result = await exchangeTwitchCode({
    code: "auth-code",
    config,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        json: async () => tokenPayload
      };
    }
  });

  assert.deepEqual(result, tokenPayload);
  assert.equal(calls[0].url, "https://id.twitch.tv/oauth2/token");
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.body.get("code"), "auth-code");
});

test("fetches Twitch user for an access token", async () => {
  const result = await fetchTwitchUser({
    accessToken: "access-token",
    config,
    fetchImpl: async (_url, options) => {
      assert.equal(options.headers["Client-Id"], "client-id");
      assert.equal(options.headers.Authorization, "Bearer access-token");
      return {
        ok: true,
        json: async () => ({
          data: [{ id: "1234", login: "streamer", display_name: "Streamer" }]
        })
      };
    }
  });

  assert.equal(result.id, "1234");
  assert.equal(result.login, "streamer");
});

test("refreshes Twitch token", async () => {
  const calls = [];
  const tokenPayload = {
    access_token: "new-access-token",
    refresh_token: "new-refresh-token",
    expires_in: 3600
  };

  const result = await refreshTwitchToken({
    refreshToken: "refresh-token",
    config,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        json: async () => tokenPayload
      };
    }
  });

  assert.deepEqual(result, tokenPayload);
  assert.equal(calls[0].url, "https://id.twitch.tv/oauth2/token");
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.body.get("grant_type"), "refresh_token");
  assert.equal(calls[0].options.body.get("refresh_token"), "refresh-token");
});
