import { pathToFileURL } from "node:url";

const baseUrl = process.env.RELAY_BASE_URL ?? "http://localhost:3000";
const userId = process.env.RELAY_USER_ID;

export function buildManualTestAlert({
  now = new Date(),
  correlationId = `manual-test:${Date.now()}`
} = {}) {
  const timestamp = now instanceof Date ? now.toISOString() : new Date(now).toISOString();
  return {
    correlationId,
    providerMessageId: correlationId,
    alert_id: correlationId,
    type: "follow",
    username: "RelayTest",
    message: "Test alert from relay server",
    amount: null,
    formatted_amount: null,
    sound_url: null,
    timestamp,
    source: "twitch_native"
  };
}

export async function sendManualTestAlert({
  fetchImpl = globalThis.fetch,
  baseUrl,
  userId,
  now = new Date()
}) {
  if (!userId) {
    throw new Error("Missing RELAY_USER_ID.");
  }

  const alert = buildManualTestAlert({ now });
  const response = await fetchImpl(`${baseUrl}/alert`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userId, alert })
  });
  const text = await response.text();

  return {
    status: response.status,
    text,
    alert
  };
}

async function runCli() {
  const result = await sendManualTestAlert({
    fetchImpl: globalThis.fetch,
    baseUrl,
    userId
  });
  console.log(`Status: ${result.status}`);
  console.log(result.text);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
