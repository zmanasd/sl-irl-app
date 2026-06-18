import test from "node:test";
import assert from "node:assert/strict";
import { runOpsProofCheck } from "../scripts/ops-proof-check.js";

test("ops proof script posts to the internal proof-check endpoint", async () => {
  let capturedUrl = null;
  let capturedOptions = null;

  const summary = await runOpsProofCheck({
    baseUrl: "https://relay.example.com/",
    internalToken: "internal-token",
    userId: "user-1",
    sendProofAlert: true,
    subscriptionAudit: false,
    fetchImpl: async (url, options) => {
      capturedUrl = url;
      capturedOptions = options;
      return {
        status: 200,
        ok: true,
        text: async () => JSON.stringify({ ok: true })
      };
    }
  });

  assert.equal(summary.passed, true);
  assert.equal(capturedUrl, "https://relay.example.com/internal/jobs/proof-check");
  assert.equal(capturedOptions.method, "POST");
  assert.equal(capturedOptions.headers["x-relay-internal-token"], "internal-token");
  assert.deepEqual(JSON.parse(capturedOptions.body), {
    userId: "user-1",
    sendProofAlert: true,
    subscriptionAudit: false
  });
});
