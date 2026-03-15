const baseUrl = process.env.RELAY_BASE_URL ?? "http://localhost:3000";
const userId = process.env.RELAY_USER_ID;

if (!userId) {
  console.error("Missing RELAY_USER_ID.");
  process.exit(1);
}

const payload = {
  userId,
  alert: {
    alert_id: `test-${Date.now()}`,
    type: "donation",
    username: "RelayTest",
    message: "Test alert from relay server",
    amount: 5,
    formatted_amount: "$5.00",
    sound_url: null,
    timestamp: new Date().toISOString(),
    source: "streamlabs"
  }
};

async function run() {
  const response = await fetch(`${baseUrl}/alert`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  const text = await response.text();
  console.log(`Status: ${response.status}`);
  console.log(text);
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
