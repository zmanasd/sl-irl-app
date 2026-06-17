# IRL Alert Relay Server

This relay is the backend proof surface for the Twitch-first MVP.

MVP delivery path:

```text
Twitch EventSub -> relay server -> APNs -> iPhone alert receipt
```

The relay, not the iOS app, is responsible for maintaining Twitch EventSub connectivity. The iOS app receives visible/audible APNs alerts in background, locked, or terminated states, and handles richer queue/audio/TTS behavior when foregrounded.

## Current Scaffold

Existing endpoints:

- `GET /auth/twitch/start?userId=...` creates a Twitch OAuth authorization URL.
- `GET /auth/twitch/callback` exchanges a Twitch OAuth code and stores server-side Twitch credentials.
- `POST /auth/twitch/refresh` refreshes a stored Twitch OAuth token.
- `GET /diagnostics` returns safe relay/user/Twitch state without raw tokens.
- `GET /diagnostics/attempts?correlationId=...` returns safe delivery attempts for a specific alert correlation ID.
- `POST /register` stores device token and Twitch-native MVP service state.
- `POST /alert` sends an APNs push for a registered user.
- `POST /soundalerts/webhook` is closed with `410 Gone` for MVP builds.
- `GET /health` confirms the server is running.
- `GET /ready` confirms global relay configuration; `GET /ready?userId=...` confirms the stricter physical-device MVP gate.

Active MVP connector:

- Twitch EventSub WebSocket connector

Post-MVP reference files for Streamlabs and StreamElements live under `post-mvp/`, outside the active relay source tree. The active relay path is Twitch EventSub only. `/register` filters non-MVP services and credentials so proof runs cannot accidentally rely on a third-party provider.

## Storage Configuration

The local JSON store is for MVP proof and small deployments. Set this before storing real Twitch OAuth credentials:

- `RELAY_DATA_PATH`
- `RELAY_STORAGE_ENCRYPTION_KEY`
- `RELAY_REQUIRE_ENCRYPTED_STORAGE`

`RELAY_STORAGE_ENCRYPTION_KEY` must decode to 32 bytes as base64 or hex. One way to generate a local key:

```text
openssl rand -base64 32
```

When the key is set, the relay encrypts the JSON payload on disk with AES-256-GCM. `/health` and `/diagnostics` report only whether storage is encrypted; they do not return the key or raw stored secrets.

Set `RELAY_REQUIRE_ENCRYPTED_STORAGE=true` in production or any proof run that uses real OAuth credentials. `/ready` returns `503` until encrypted storage is active.

## MVP Next Steps

1. Configure APNs and Twitch OAuth credentials against a reachable HTTPS relay.
2. Register a physical iPhone from the app and confirm `/ready?userId=<relay-user-id>` succeeds.
3. Run `npm run proof` and store the JSON output with iOS diagnostics screenshots.
4. Trigger Twitch EventSub mock/live events and verify exact delivery-attempt correlation.
5. Complete the physical-device checklist in `../docs/MVP_PROOF_CHECKLIST.md`.

## APNs Configuration

Set these environment variables before testing APNs:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY` or `APNS_PRIVATE_KEY_PATH`
- `APNS_PRODUCTION` (`true` for production)

## Twitch Configuration

Set these environment variables before implementing or testing Twitch OAuth/EventSub:

- `TWITCH_CLIENT_ID`
- `TWITCH_CLIENT_SECRET`
- `TWITCH_REDIRECT_URI`
- `TWITCH_TOKEN_REFRESH_WINDOW_SECONDS` (default `600`)
- `TWITCH_TOKEN_REFRESH_INTERVAL_SECONDS` (default `300`, set `0` to disable scheduled refresh)

The active MVP connector should use Twitch EventSub WebSockets and OAuth user tokens with the scopes required for the supported event types.

OAuth start endpoint:

```text
GET /auth/twitch/start?userId=<relay-user-id>
```

The endpoint returns JSON containing `authUrl`, `state`, and `scope`. Use `redirect=true` to redirect the browser directly to Twitch.

Token refresh endpoints:

```text
POST /auth/twitch/refresh
POST /auth/twitch/refresh-due
```

`refresh-due` refreshes stored Twitch tokens that are expired or inside the configured refresh window. Refresh attempts are recorded in diagnostics without raw access or refresh tokens.

## Testing

Use Twitch CLI mock WebSocket events before relying on real stream activity. MVP proof tests should produce a single traceable correlation chain:

```text
twitch_message_id -> relay_event_id -> apns_id -> ios_received_id -> queue_event_id -> playback_event_id
```

Existing manual APNs test path:

```text
RELAY_USER_ID=... RELAY_BASE_URL=http://localhost:3000 npm run test-alert
```

Preferred proof path:

```text
RELAY_USER_ID=... RELAY_BASE_URL=http://localhost:3000 npm run proof
```

The proof command checks relay health, checks `/ready?userId=...`, captures diagnostics before the alert, sends one correlated test alert, captures diagnostics after the alert, and exits non-zero if the relay cannot show both per-user readiness and a sent delivery attempt for the generated correlation ID.

Exact delivery lookup:

```text
curl "<relay-url>/diagnostics/attempts?correlationId=<correlation-id>"
```

Use this when a copied iOS diagnostics snapshot or Event Log screenshot contains a correlation ID that needs to be matched back to relay/APNs evidence.

Readiness check:

```text
curl "<relay-url>/ready"
curl "<relay-url>/ready?userId=<relay-user-id>"
```

`/ready` returns `200` only when required APNs and Twitch OAuth configuration are present. If `RELAY_REQUIRE_ENCRYPTED_STORAGE=true`, it also requires encrypted local storage. Add `userId` for physical-device validation; that stricter check also requires a registered device token, stored Twitch OAuth tokens, a session-ready Twitch EventSub connector, fresh keepalive state, and successful required EventSub subscriptions.

For physical-device validation, use `../docs/MVP_PROOF_CHECKLIST.md` and capture the relay diagnostics before and after each tested correlation ID.

Automated tests:

```text
npm test
```

Most proof-harness tests run without installing relay runtime dependencies. HTTP route tests require the relay runtime packages (`express`, `@parse/node-apn`, etc.); if `node_modules` is absent, those tests are skipped with an explicit message.

Delivery attempts are recorded in relay diagnostics with:

- `correlationId`
- provider message ID
- source/type
- delivery status
- device-token fingerprint and length, never the raw token
- APNs sent/failed counts
- APNs IDs where available
- failure reason where available

`GET /diagnostics` intentionally reports token/device-token presence and a short device-token fingerprint without returning raw secrets.

Storage diagnostics include:

- storage type
- encrypted/unencrypted status

Provider message dedupe diagnostics include:

- number of tracked provider message IDs
- recent provider message IDs used for duplicate suppression

Duplicate provider messages are recorded as delivery attempts with status `duplicate_provider_message` and are not forwarded to APNs.

Readiness diagnostics include safe APNs and Twitch OAuth configuration state:

- APNs key/team/bundle/private-key presence flags
- APNs production flag
- missing APNs environment variable names
- Twitch client/secret/redirect presence flags
- Twitch OAuth scopes requested by the relay

Connector diagnostics include Twitch EventSub state:

- connection/session status
- broadcaster ID
- session ID
- reconnect URL presence
- connection/reconnect counts
- last connect/disconnect time
- last keepalive time
- keepalive stale flag
- last notification/revocation time
- subscription creation results
- last connector error

Connector recovery diagnostics include:

- last full connector sync timestamp
- synced user count
- failed user count
- per-user sync results

Startup runs a recovery pass that refreshes due Twitch tokens and syncs connectors for stored users.

Token refresh diagnostics include:

- user ID
- refreshed/failed status
- new expiry time where available
- scopes
- failure reason without raw tokens

## Anti-Guesswork Rule

No relay behavior should be treated as MVP-ready unless it has:

- isolated proof output
- automated proof output where possible
- structured logs
- correlation IDs
- pass/fail criteria
- a documented pivot rule
