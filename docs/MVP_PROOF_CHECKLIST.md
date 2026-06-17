# MVP Proof Checklist

This checklist turns real-device testing into a repeatable evidence trail. Do not mark an MVP delivery path as working unless the checklist produces a clear pass or a concrete failure point.

## 1. Test Run Header

Record this before each run:

- Date and time
- Git branch and commit SHA
- iPhone model and iOS version
- Network type
- Relay URL used by the app
- Twitch test source: Twitch CLI mock, controlled real event, or live stream event
- Tester

## 2. Preflight

Relay:

- `GET /health` returns success.
- `GET /ready?userId=<relay-user-id>` returns success before starting physical-device MVP validation.
- `GET /diagnostics` shows the expected registered user.
- `GET /diagnostics` shows APNs configuration presence without exposing secrets.
- `GET /diagnostics` shows Twitch connector status, session status, and subscription results.
- `GET /diagnostics` shows the latest Twitch token refresh attempt after `/auth/twitch/refresh-due` runs.
- `GET /diagnostics` shows provider message dedupe tracking after Twitch events arrive.
- `GET /diagnostics` shows connector recovery after relay restart.
- `GET /diagnostics` shows encrypted relay storage before using real Twitch OAuth credentials.
- Relay environment contains `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET`, `TWITCH_REDIRECT_URI`, token refresh variables, and APNs variables.

iPhone:

- Devices & Connections -> Check MVP Readiness succeeds and shows `Ready`.
- Devices & Connections -> Refresh Relay Diagnostics succeeds and shows the expected relay snapshot.
- Settings -> Delivery Diagnostics shows Push Permission as `Authorized` or `Provisional`.
- Settings -> Delivery Diagnostics shows APNs Token as `Available`.
- Settings -> Delivery Diagnostics shows Relay Device with the relay-side device-token fingerprint after tapping Refresh Relay Diagnostics.
- Settings -> Delivery Diagnostics shows the relay URL expected for this physical device. `http://localhost:3000` is only valid for simulator/local host tests.
- Settings -> Background & Notifications has Relay URL set to a reachable HTTPS tunnel or production relay URL for physical-device tests.
- Settings -> Delivery Diagnostics shows the expected relay user.
- Settings -> Delivery Diagnostics -> Relay Snapshot shows the current relay response after tapping Refresh Relay Diagnostics.
- Settings -> Delivery Diagnostics -> Copy Diagnostics Snapshot produces a secret-safe text snapshot for the evidence package.
- iOS notification settings allow IRL Alert notifications and sound.

## 3. Isolated Twitch EventSub Proof

In the app, open Devices & Connections -> Connect Twitch. The app asks the relay for a Twitch OAuth URL and opens it in the browser.

Then trigger one supported Twitch event with Twitch CLI mock events or a controlled real event.

Evidence to capture:

- Twitch provider message ID.
- Relay normalized alert `correlationId`.
- Alert type and username.
- Relay dedupe outcome.
- Provider dedupe count before and after replay/reconnect.
- Twitch connector diagnostics after the event.

Pass criteria:

- The event is normalized once.
- The normalized alert contains `correlationId` and provider message ID.
- Repeating or reconnecting does not duplicate the same provider message ID.

Failure pivot:

- If mock events cannot normalize reliably, stop app work and fix the Twitch connector or reduce the supported event set.

## 4. Isolated APNs Proof

Register the device from Devices & Connections -> Register This iPhone.

Then run the automated relay proof harness:

```text
RELAY_USER_ID=<relay-user-id> RELAY_BASE_URL=<reachable-relay-url> npm run proof
```

The command performs:

- `GET /health`
- `GET /ready?userId=...`
- `GET /diagnostics` before the test alert
- `POST /alert` with a generated `correlationId`
- `GET /diagnostics` after the test alert
- `GET /diagnostics/attempts?correlationId=...` for exact delivery-attempt lookup

It exits non-zero if global relay readiness fails, the per-user readiness gate fails, the relay user is missing, the APNs token is missing, the Twitch EventSub connector is not session-ready, the alert send fails, or the final diagnostics do not contain a sent delivery attempt for the same correlation ID.

You can also send a relay test alert manually from either:

- Devices & Connections -> Send Relay Test Alert
- Settings -> Delivery Diagnostics -> Send Relay Test Alert

Terminal fallback for sending only the alert:

Command:

```text
RELAY_USER_ID=<relay-user-id> RELAY_BASE_URL=<reachable-relay-url> npm run test-alert
```

Evidence to capture:

- `npm run proof` JSON output.
- Devices & Connections `MVP Readiness` value.
- Test alert `correlationId`.
- Settings -> Delivery Diagnostics `Last Relay Test`.
- Settings -> Delivery Diagnostics `Relay Snapshot`, `Twitch Status`, and `Relay Delivery`.
- Relay delivery attempt status.
- Exact relay attempt lookup for the tested `correlationId`.
- APNs status and failure reason, if any.
- `apns-id` where available.
- Device-token fingerprint and length from relay diagnostics, never the raw token.

Pass criteria:

- 9 out of 10 alerts produce an audible iOS notification while the phone is locked or the app is backgrounded on a stable network.
- Any failed attempt identifies a relay, APNs, entitlement, token, or device-state reason.

Failure pivot:

- If APNs cannot meet the 9/10 threshold, do not tune PiP or silent audio. Decide whether the MVP promise must be foreground-only or whether APNs entitlement/device configuration needs correction.

## 5. Foreground iOS Receipt Proof

Open the app and send a relay test alert while the app is active.

Evidence to capture:

- Settings -> Delivery Diagnostics `Push Receipts` count before and after the alert.
- Settings -> Delivery Diagnostics `Last Correlation`.
- Settings -> Delivery Diagnostics `Last Received`.
- Event Log entry showing the same correlation ID.
- Alert queue/audio/TTS behavior.

Pass criteria:

- The notification is accepted once.
- The same correlation ID appears in Delivery Diagnostics and Event Log.
- Audio/TTS runs once for enabled alert types.

Failure pivot:

- If the alert is dropped, use `Last Drop` to fix parser, dedupe, or payload shape before adding any new integration.

## 6. End-To-End MVP Proof

Run the full path:

```text
Twitch EventSub -> relay normalization -> APNs send -> iPhone receipt -> Event Log -> audio/TTS
```

For each run, capture one row:

| State | Correlation ID | Provider Message ID | APNs Result | iOS Receipt | Event Log | Audio/TTS | Pass/Fail | Notes |
|---|---|---|---|---|---|---|---|---|
| Foreground | | | | | | | | |
| Backgrounded | | | | | | | | |
| Locked | | | | | | | | |
| Terminated | | | | | | | | |
| Network reconnect | | | | | | | | |
| Relay restart | | | | | | | | |
| Token refresh | | | | | | | | |
| Permission denied | | | | | | | | |

MVP pass criteria:

- Twitch mock or real event produces one traceable correlation ID across relay diagnostics and the iOS app.
- Foreground event routes into the queue, Event Log, and audio/TTS once.
- Locked/backgrounded event produces an audible iOS notification.
- Diagnostics identify the subsystem responsible for each failure.
- Relay restart test shows connector recovery in diagnostics and no duplicate provider messages.
- Token refresh test records a refreshed or failed attempt in relay diagnostics without exposing raw tokens.

## 7. Evidence Package

Keep this package for each validation session:

- `npm run proof` JSON output.
- Copied iOS diagnostics snapshot.
- Relay `/diagnostics` JSON before and after the run.
- Relay logs for the tested correlation IDs.
- Relay storage diagnostics showing encrypted storage for any run using real OAuth credentials.
- iOS Settings -> Delivery Diagnostics screenshot.
- Event Log screenshot for the tested correlation IDs.
- Notes for any entitlement, network, token, or permission changes made during the run.

The relay user fingerprint, relay delivery-attempt fingerprint, and copied iOS diagnostics snapshot should agree for the same run. If evidence cannot identify where an alert stopped, the run fails the anti-guesswork requirement even if one notification happened to arrive.
