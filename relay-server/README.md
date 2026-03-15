# IRL Alert Relay Server (Phase 5A)

This is the early scaffold for the backend relay described in Phase 5A.

## What exists
- `POST /register` to store device token + service list
- `POST /presence` to toggle direct-connection state
- `GET /health` to confirm the server is running

## Next steps
- Add service connectors (Streamlabs, Twitch, StreamElements, SoundAlerts)
- Add APNs integration to forward alerts
- Add persistence for registrations (DB or KV store)
