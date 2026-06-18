import { createRemoteJWKSet, jwtVerify } from "jose";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export function bearerTokenFromRequest(req) {
  const header = req.get?.("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? null;
}

export function requireBetaSession({ registry }) {
  return (req, res, next) => {
    const token = bearerTokenFromRequest(req);
    const session = registry.getSession(token);

    if (!session) {
      return res.status(401).json({
        error: "A valid beta session bearer token is required.",
        code: "BETA_SESSION_REQUIRED"
      });
    }

    req.relaySession = session;
    req.relayUserId = session.userId;
    return next();
  };
}

export async function verifyAppleIdentityToken({
  identityToken,
  env = process.env,
  now = new Date()
}) {
  if (!identityToken) {
    const error = new Error("identityToken is required.");
    error.code = "APPLE_ID_TOKEN_REQUIRED";
    throw error;
  }

  if (env.APPLE_AUTH_DEV_BYPASS === "true") {
    if (env.NODE_ENV === "production" || env.RELAY_ENVIRONMENT === "production-beta") {
      const error = new Error("APPLE_AUTH_DEV_BYPASS is not allowed in production-beta.");
      error.code = "APPLE_DEV_BYPASS_FORBIDDEN";
      throw error;
    }

    return {
      subject: identityToken,
      email: null,
      emailVerified: null,
      issuer: "local-dev",
      audience: "local-dev",
      expiresAt: new Date(now.getTime() + 60 * 60 * 1000).toISOString()
    };
  }

  const audience = env.APPLE_CLIENT_ID ?? env.APNS_BUNDLE_ID;
  if (!audience) {
    const error = new Error("APPLE_CLIENT_ID or APNS_BUNDLE_ID is required for Apple Sign in verification.");
    error.code = "APPLE_AUDIENCE_REQUIRED";
    throw error;
  }

  const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
    issuer: APPLE_ISSUER,
    audience
  });

  return {
    subject: payload.sub,
    email: payload.email ?? null,
    emailVerified: payload.email_verified ?? null,
    issuer: payload.iss,
    audience: payload.aud,
    expiresAt: payload.exp ? new Date(payload.exp * 1000).toISOString() : null
  };
}
