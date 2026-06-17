import crypto from "crypto";
import { twitchRequiredScopes } from "./connectors/twitch-subscriptions.js";

const TWITCH_AUTHORIZE_URL = "https://id.twitch.tv/oauth2/authorize";
const TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token";
const TWITCH_USERS_URL = "https://api.twitch.tv/helix/users";

export function twitchOAuthConfigFromEnv(env = process.env) {
  return {
    clientId: env.TWITCH_CLIENT_ID,
    clientSecret: env.TWITCH_CLIENT_SECRET,
    redirectUri: env.TWITCH_REDIRECT_URI,
    scopes: twitchRequiredScopes()
  };
}

export function assertTwitchOAuthConfig(config) {
  const missing = [];
  if (!config.clientId) missing.push("TWITCH_CLIENT_ID");
  if (!config.clientSecret) missing.push("TWITCH_CLIENT_SECRET");
  if (!config.redirectUri) missing.push("TWITCH_REDIRECT_URI");
  if (missing.length) {
    const error = new Error(`Missing Twitch OAuth config: ${missing.join(", ")}`);
    error.code = "TWITCH_OAUTH_CONFIG_MISSING";
    error.missing = missing;
    throw error;
  }
}

export function twitchOAuthDiagnostics(env = process.env) {
  const config = twitchOAuthConfigFromEnv(env);
  const missing = [];
  if (!config.clientId) missing.push("TWITCH_CLIENT_ID");
  if (!config.clientSecret) missing.push("TWITCH_CLIENT_SECRET");
  if (!config.redirectUri) missing.push("TWITCH_REDIRECT_URI");

  return {
    configured: missing.length === 0,
    hasClientId: Boolean(config.clientId),
    hasClientSecret: Boolean(config.clientSecret),
    hasRedirectUri: Boolean(config.redirectUri),
    scopes: config.scopes,
    missing
  };
}

export function createTwitchOAuthStart({ userId, config, now = new Date() }) {
  assertTwitchOAuthConfig(config);
  if (!userId || typeof userId !== "string") {
    const error = new Error("userId is required.");
    error.code = "USER_ID_REQUIRED";
    throw error;
  }

  const state = crypto.randomBytes(24).toString("base64url");
  const scope = config.scopes.join(" ");
  const authUrl = new URL(TWITCH_AUTHORIZE_URL);
  authUrl.searchParams.set("client_id", config.clientId);
  authUrl.searchParams.set("redirect_uri", config.redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", scope);
  authUrl.searchParams.set("state", state);
  authUrl.searchParams.set("force_verify", "true");

  return {
    authUrl: authUrl.toString(),
    state,
    scope,
    pendingState: {
      state,
      userId,
      createdAt: now.toISOString()
    }
  };
}

export async function exchangeTwitchCode({
  code,
  config,
  fetchImpl = globalThis.fetch
}) {
  assertTwitchOAuthConfig(config);
  if (!code) {
    const error = new Error("OAuth code is required.");
    error.code = "TWITCH_CODE_REQUIRED";
    throw error;
  }
  if (typeof fetchImpl !== "function") {
    const error = new Error("fetch is unavailable.");
    error.code = "FETCH_UNAVAILABLE";
    throw error;
  }

  const body = new URLSearchParams();
  body.set("client_id", config.clientId);
  body.set("client_secret", config.clientSecret);
  body.set("code", code);
  body.set("grant_type", "authorization_code");
  body.set("redirect_uri", config.redirectUri);

  const response = await fetchImpl(TWITCH_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body
  });

  if (!response.ok) {
    const text = await response.text();
    const error = new Error(`Twitch token exchange failed: ${response.status} ${text}`);
    error.code = "TWITCH_TOKEN_EXCHANGE_FAILED";
    error.status = response.status;
    throw error;
  }

  return response.json();
}

export async function refreshTwitchToken({
  refreshToken,
  config,
  fetchImpl = globalThis.fetch
}) {
  assertTwitchOAuthConfig(config);
  if (!refreshToken) {
    const error = new Error("Twitch refresh token is required.");
    error.code = "TWITCH_REFRESH_TOKEN_REQUIRED";
    throw error;
  }
  if (typeof fetchImpl !== "function") {
    const error = new Error("fetch is unavailable.");
    error.code = "FETCH_UNAVAILABLE";
    throw error;
  }

  const body = new URLSearchParams();
  body.set("client_id", config.clientId);
  body.set("client_secret", config.clientSecret);
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", refreshToken);

  const response = await fetchImpl(TWITCH_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body
  });

  if (!response.ok) {
    const text = await response.text();
    const error = new Error(`Twitch token refresh failed: ${response.status} ${text}`);
    error.code = "TWITCH_TOKEN_REFRESH_FAILED";
    error.status = response.status;
    throw error;
  }

  return response.json();
}

export async function fetchTwitchUser({
  accessToken,
  config,
  fetchImpl = globalThis.fetch
}) {
  assertTwitchOAuthConfig(config);
  if (!accessToken) {
    const error = new Error("Twitch access token is required.");
    error.code = "TWITCH_ACCESS_TOKEN_REQUIRED";
    throw error;
  }
  if (typeof fetchImpl !== "function") {
    const error = new Error("fetch is unavailable.");
    error.code = "FETCH_UNAVAILABLE";
    throw error;
  }

  const response = await fetchImpl(TWITCH_USERS_URL, {
    headers: {
      "Client-Id": config.clientId,
      "Authorization": `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    const text = await response.text();
    const error = new Error(`Twitch user fetch failed: ${response.status} ${text}`);
    error.code = "TWITCH_USER_FETCH_FAILED";
    error.status = response.status;
    throw error;
  }

  const payload = await response.json();
  const user = payload?.data?.[0];
  if (!user?.id) {
    const error = new Error("Twitch user not found for token.");
    error.code = "TWITCH_USER_NOT_FOUND";
    throw error;
  }

  return user;
}
