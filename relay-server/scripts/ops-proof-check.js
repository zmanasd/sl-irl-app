import { pathToFileURL } from "node:url";

const DEFAULT_BASE_URL = "http://localhost:3000";

function normalizeBaseUrl(baseUrl = DEFAULT_BASE_URL) {
  return baseUrl.replace(/\/+$/, "");
}

async function requestJson({ fetchImpl, url, options = {} }) {
  const response = await fetchImpl(url, options);
  const text = await response.text();
  let body = null;

  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { raw: text };
    }
  }

  return {
    status: response.status,
    ok: response.ok,
    body
  };
}

export async function runOpsProofCheck({
  baseUrl = DEFAULT_BASE_URL,
  internalToken = process.env.RELAY_INTERNAL_TOKEN,
  userId = process.env.RELAY_PROOF_USER_ID,
  sendProofAlert = process.env.RELAY_PROOF_SEND_ALERT === "true",
  subscriptionAudit = process.env.RELAY_PROOF_SUBSCRIPTION_AUDIT !== "false",
  fetchImpl = globalThis.fetch
} = {}) {
  if (typeof fetchImpl !== "function") {
    throw new Error("A fetch implementation is required.");
  }

  const normalizedBaseUrl = normalizeBaseUrl(baseUrl);
  const response = await requestJson({
    fetchImpl,
    url: `${normalizedBaseUrl}/internal/jobs/proof-check`,
    options: {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(internalToken ? { "x-relay-internal-token": internalToken } : {})
      },
      body: JSON.stringify({
        userId: userId || null,
        sendProofAlert,
        subscriptionAudit
      })
    }
  });

  return {
    passed: response.status === 200 && response.body?.ok === true,
    status: response.status,
    baseUrl: normalizedBaseUrl,
    body: response.body
  };
}

async function runCli() {
  const summary = await runOpsProofCheck({
    baseUrl: process.env.RELAY_BASE_URL ?? DEFAULT_BASE_URL
  });

  console.log(JSON.stringify(summary, null, 2));
  if (!summary.passed) {
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
