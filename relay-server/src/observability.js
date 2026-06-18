let sentry = null;

export async function initSentry({
  env = process.env,
  logger = console
} = {}) {
  if (!env.SENTRY_DSN) {
    return { configured: false };
  }

  const Sentry = await import("@sentry/node");
  sentry = Sentry;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.RELAY_ENVIRONMENT ?? env.NODE_ENV ?? "development",
    tracesSampleRate: Number(env.SENTRY_TRACES_SAMPLE_RATE ?? 0.05),
    sendDefaultPii: false
  });
  logger.info?.("Sentry initialized.");
  return { configured: true };
}

export function captureException(error, context = {}) {
  if (!sentry) return;
  sentry.captureException(error, {
    extra: context
  });
}
