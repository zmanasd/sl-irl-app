# IRL Alert Relay Server (Phase 5A)

This is the early scaffold for the backend relay described in Phase 5A.

## What exists
- `POST /register` to store device token + service list + credentials
- `POST /presence` to toggle direct-connection state
- `POST /alert` to send an APNs push for a registered user
- `POST /soundalerts/webhook` to forward SoundAlerts-style payloads (manual integration)
- `GET /health` to confirm the server is running

## Next steps
- Add service connectors (Twitch, SoundAlerts)
- Add persistence for registrations (DB or KV store)

## APNs configuration
Set these env vars before testing `/alert`:
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY` or `APNS_PRIVATE_KEY_PATH`
- `APNS_PRODUCTION` (set to `true` for production)

See `.env.example` for a starter template.

## Testing
You can trigger a test push with:
- `RELAY_USER_ID=... RELAY_BASE_URL=http://localhost:3000 npm run test-alert`

## SoundAlerts integration
No official SoundAlerts API/websocket docs were found during implementation. Use `/soundalerts/webhook` as a manual bridge if you can forward SoundAlerts events via a custom webhook or proxy.

## Streamlabs connector
If you register credentials with `service=streamlabs` and `type=socket`, the relay will connect to Streamlabs and forward alerts when direct connection is inactive.

## StreamElements connector
StreamElements uses the Astro websocket (`wss://astro.streamelements.com`) and requires a token with a `token_type` of `oauth`, `jwt`, or `apikey`. Use `service=stream_elements` and pass credentials with:
- `type=oauth` for OAuth tokens
- `type=socket` for API key tokens (mapped to `apikey`)

## Twitch connector
Twitch uses EventSub WebSockets and requires:
- `TWITCH_CLIENT_ID` environment variable
- OAuth user token with required scopes
Use `service=twitch_native` and `type=oauth` credentials.
