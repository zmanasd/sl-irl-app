# IRL Alert

IRL Alert is an iOS companion app for mobile IRL streamers who need reliable Twitch interaction alerts while using another streaming app.

The MVP is now scoped to one proof-first delivery path:

**Twitch EventSub -> relay server -> APNs -> iPhone alert receipt -> foreground queue/log/audio**

The app no longer treats PiP, silent audio, Browser Source parsing, or multi-provider alert integrations as MVP requirements. Those paths remain post-MVP work until the Twitch-first proof is validated on a real device.

## MVP Behavior

- The relay server maintains Twitch EventSub WebSocket sessions.
- The relay normalizes Twitch events and sends visible, audible APNs notifications.
- The iOS app registers its APNs device token with the relay.
- The iOS Connections screen starts Twitch OAuth through the relay, registers the iPhone, and sends a correlated relay test alert.
- When the app is foregrounded, alert payloads are deduped, persisted, queued, and played through native audio/TTS.
- When the app is backgrounded, locked, or terminated, MVP alert awareness comes from iOS notifications rather than continuous in-app execution.

## Anti-Guesswork Rule

No platform-sensitive capability enters the production MVP path until it has passed an isolated proof harness with logs, correlation IDs, pass/fail criteria, and a documented pivot rule.

See `IMPLEMENTATION_PLAN.md` for the active implementation plan.
Use `docs/MVP_PROOF_CHECKLIST.md` for physical-device validation and evidence capture.
