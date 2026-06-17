# IRL Alert App - Twitch-First MVP Reset Implementation Plan

## 1. Summary

This plan resets the project around one defensible MVP vertical slice:

**Twitch EventSub -> relay server -> APNs -> iPhone alert receipt -> foreground queue/log/audio**

The previous plan expanded the MVP across PiP, Streamlabs, StreamElements, SoundAlerts, Browser Source parsing, custom third-party alert media, and multi-provider background delivery before the core concept had been proven. That created too much platform and integration risk at once.

The reset keeps the useful foundation already present in the repo:

- SwiftUI app shell and screens
- Alert queue
- Native audio/TTS playback
- Local event store
- Push notification plumbing
- Notification Service Extension scaffold
- Node relay server scaffold
- Initial Twitch EventSub connector work

The reset removes these from the MVP critical path:

- PiP as a background execution mechanism
- Silent audio backgrounding
- Streamlabs, StreamElements, and SoundAlerts
- Browser Source URL parsing
- Custom third-party alert sounds
- Donations/tips

The MVP is complete only when a streamer can connect Twitch, enable notifications, trigger supported Twitch events, hear alerts while using another app or with the phone locked, and review received events in the app.

## 2. Anti-Guesswork Delivery Process

No platform-sensitive capability may enter the production MVP path until it has passed an isolated proof harness with observable evidence.

### 2.1 Assumption Ledger

Before implementation, create an assumption ledger for every risky claim. Each item must include:

- Assumption
- Proof harness
- Pass criteria
- Failure evidence to collect
- Kill or pivot rule
- Owning subsystem

Initial assumptions:

| Assumption | Proof Harness | Pass Criteria | Pivot Rule |
|---|---|---|---|
| Twitch EventSub WebSocket can deliver MVP events to the relay | Minimal relay with Twitch CLI mock events | All supported mock events normalize correctly and dedupe after reconnect | Move to webhook transport or reduce supported event set |
| APNs can deliver audible alerts while the phone is locked/backgrounded | Relay test endpoint sending APNs to physical iPhone | 9/10 audible notifications under stable network | Reframe MVP as foreground companion or revise alert-delivery promise |
| iOS can route foreground notification payloads into the queue once | Minimal app-side notification parser and queue path | Same alert appears once in queue/log/playback | Tighten dedupe model before any new feature work |
| Diagnostics can identify where alert delivery failed | Correlation ID through all systems | Every test alert has a trace from relay to iOS receipt or a clear failure point | Block MVP integration until observability exists |

### 2.2 Proof Harness First

Each risky subsystem must be proven in isolation before being integrated into the main app flow:

1. Twitch EventSub relay proof
2. APNs delivery proof
3. iOS notification receipt proof
4. Foreground queue/audio/TTS proof
5. End-to-end correlation proof

The implementer must not continue broad tuning if a proof repeatedly fails. Capture evidence, compare against the pivot rule, and decide explicitly.

### 2.3 Correlation IDs

Every alert must carry a correlation chain:

```text
twitch_message_id -> relay_event_id -> apns_id -> ios_received_id -> queue_event_id -> playback_event_id
```

Logs must make it possible to answer exactly where an alert stopped:

- Twitch/WebSocket
- Relay normalization
- APNs send
- APNs delivery or iOS receipt
- App queue
- Audio/TTS playback

### 2.4 Diagnostics

The app must include a diagnostics screen or export before MVP validation. It must show:

- Notification permission state
- APNs device-token registration timestamp
- Relay registration status
- Last received notification correlation ID
- Last queued alert correlation ID
- Last audio/TTS playback start/finish status
- Current audio route/category

The relay must expose diagnostics or health output for:

- Twitch session state
- EventSub subscription status
- Last keepalive timestamp
- Reconnect count
- OAuth token refresh state
- Last normalized alert
- Last APNs send result
- `apns-id` where available

### 2.5 Hard Gates

Feature work cannot graduate into the MVP path unless the related proof gate passes:

- Twitch mock events reach relay normalization with no duplicates.
- Relay sends APNs and records success/failure with correlation ID.
- Locked/backgrounded iPhone receives audible notification 9/10 times on stable network.
- Foreground notifications route into the alert queue once.
- Reconnect tests do not duplicate alerts.

## 3. Implementation Phases

### Phase 0 - Documentation And Scope Reset

Goal: make the new MVP definition unambiguous before code work begins.

Tasks:

- Update the PRD so MVP means Twitch Native EventSub only.
- Mark PiP, silent audio, Browser Source parsing, Streamlabs, StreamElements, SoundAlerts, custom media, and donations/tips as post-MVP.
- Keep the Phase 5A PiP report and walkthrough as diagnostic history.
- Add the assumption ledger to project documentation.
- Record that background alert delivery for MVP is APNs-based, not continuous in-app execution.

Exit criteria:

- PRD and implementation plan agree on the MVP scope.
- No MVP task depends on PiP or silent audio.

### Phase 1 - Isolated Twitch EventSub Relay Proof

Goal: prove Twitch events can be received and normalized by the relay before app UX changes.

Tasks:

- Implement Twitch OAuth authorization-code flow with refresh-token support.
- Keep Twitch OAuth tokens server-side only.
- Store tokens with production-ready encryption design; local dev storage may be simpler but must be clearly marked as dev-only.
- Fetch the broadcaster user ID from Twitch after OAuth.
- Connect to Twitch EventSub WebSocket.
- Subscribe to MVP Twitch events:
  - `channel.follow`
  - `channel.subscribe`
  - `channel.subscription.gift`
  - `channel.subscription.message`
  - `channel.cheer`
  - `channel.raid`
  - optionally `channel.channel_points_custom_reward_redemption.add`
- Normalize every Twitch event into the app alert shape with `correlationId` and provider message ID.
- Use Twitch CLI mock WebSocket events for repeatable testing before live stream testing.
- Add dedupe by Twitch message ID.
- Handle EventSub keepalive and reconnect messages.

Exit criteria:

- All supported Twitch CLI mock events produce normalized alert payloads.
- Relay logs show correlation IDs and provider message IDs.
- Reconnect does not duplicate alerts.

### Phase 2 - Isolated APNs Delivery Proof

Goal: prove the relay can send audible alerts to a real iPhone in background/locked states.

Tasks:

- Add or harden a relay test-alert endpoint.
- Send visible APNs notifications with:
  - alert title/body
  - bundled/default notification sound
  - normalized alert payload
  - `correlationId`
- Log APNs result, Apple response status, `apns-id`, alert type, and device-token hash.
- Do not rely on silent push for MVP alert delivery.
- Use physical-device testing with a valid push entitlement.

Exit criteria:

- On stable network, 9/10 locked or backgrounded test alerts produce audible notification.
- Failed APNs attempts identify a concrete relay/APNs error.
- App receives foreground notification payloads when active.

### Phase 3 - iOS MVP Integration

Goal: integrate the proven relay and APNs path into the app without reintroducing background-execution guesswork.

Tasks:

- Simplify onboarding to Twitch connection plus notification permission.
- Register the APNs device token with the relay.
- Add relay registration status to the UI.
- Remove `SilentAudioPlayer` from shipping startup behavior.
- Keep PiP settings and PiP startup out of the MVP UX.
- Parse normalized notification payloads into the existing alert model.
- Dedupe by `correlationId` or provider message ID.
- Foreground behavior:
  - enqueue alert
  - persist event
  - play native audio/TTS using existing services
- Background/locked/terminated behavior:
  - rely on iOS notification display and sound
  - persist/reconcile event when the app next receives or opens the payload
- Add diagnostics screen/export.

Exit criteria:

- Foreground notification routes into queue/log/playback once.
- Background or locked notification is audible.
- Diagnostics show the same correlation ID across receipt, queue, and playback where applicable.

### Phase 4 - Relay Persistence And Reliability

Goal: harden the relay enough that MVP tests are meaningful and repeatable.

Tasks:

- Add durable storage for:
  - users
  - devices
  - Twitch OAuth tokens
  - EventSub session/subscription state
  - recent provider message IDs
  - recent delivery attempts
- Add token refresh handling.
- Add relay restart recovery.
- Add Twitch keepalive timeout detection.
- Add health/diagnostics endpoints.
- Add manual "send test alert" flow from app to relay.

Exit criteria:

- Relay restart does not lose registered users/devices.
- Token refresh path works in test.
- Health output identifies Twitch, relay, APNs, and device registration state.
- `npm run proof` captures health, `/ready?userId=...`, before/after diagnostics, a correlated test alert, and a pass/fail summary without exposing secrets.

### Phase 5 - End-To-End MVP Validation

Goal: validate the complete Twitch-first MVP on a real device.

Test states:

- App foreground
- App backgrounded
- Phone locked
- App terminated
- Network drop/reconnect
- Expired Twitch token refresh
- Notification permission denied

Exit criteria:

- Twitch mock or real event produces one traceable correlation ID across relay, APNs, iOS receipt, and event log.
- Foreground event plays native audio/TTS.
- Background/locked event produces audible notification.
- No duplicate event-log or queue entries after reconnect.
- Permission-denied and relay-disconnected states are visible and actionable.
- Each real-device validation session stores the `npm run proof` JSON output alongside iOS diagnostics screenshots and relay logs for the tested correlation IDs.

## 4. Interfaces And Payloads

### 4.1 Normalized Alert Payload

All relay-to-app alert payloads must include:

```json
{
  "correlationId": "string",
  "providerMessageId": "string",
  "source": "twitch_native",
  "type": "follow | subscription | bits | raid | channel_points",
  "username": "string",
  "message": "string|null",
  "amount": "number|null",
  "formattedAmount": "string|null",
  "timestamp": "ISO-8601 string"
}
```

The app may map this into `AlertEvent`, but it must preserve `correlationId` or `providerMessageId` for dedupe and diagnostics.

### 4.2 Relay Capabilities

The relay must provide:

- Twitch OAuth start/callback
- Device registration/update
- Twitch EventSub session management
- Test alert send
- Health/diagnostics
- APNs alert forwarding

### 4.3 App Capabilities

The app must provide:

- Twitch connect entry point
- Notification permission prompt/status
- Relay registration status
- Alert event log
- Foreground queue/audio/TTS
- Diagnostics screen/export
- Test alert trigger

## 5. Test Plan

### Unit Tests

- Twitch event normalization for each supported event type.
- Dedupe by provider message ID and correlation ID.
- Notification payload parser.
- Queue processing and overflow behavior.
- OAuth token refresh decision logic.

### Relay Integration Tests

- Twitch CLI mock events reach normalized alert output.
- EventSub reconnect does not duplicate alerts.
- APNs sender records success/failure with correlation ID.
- Relay restart restores users/devices/subscription state.

### iOS Tests

- Foreground notification routes to queue once.
- Alert payload persists to event log.
- Permission-denied state displays blocked status.
- Diagnostics screen reports latest token, relay, notification, queue, and playback state.
- Diagnostics screen reports the same per-user MVP readiness gate used by `npm run proof`.

### Physical Device Acceptance Tests

- 9/10 audible APNs notifications while locked/backgrounded on stable network.
- Foreground alert plays native audio/TTS.
- Terminated app still receives visible/audible notification.
- Reconnect test produces no duplicate queue entries.
- One correlation ID is traceable from relay to iOS diagnostics.
- `GET /ready?userId=<relay-user-id>` and the app's Check MVP Readiness action agree before APNs acceptance testing starts.

## 6. Post-MVP Work

These features remain intentionally out of scope until the Twitch-first MVP passes:

- Streamlabs integration
- StreamElements integration
- SoundAlerts integration
- Donations/tips
- Browser Source URL parsing
- Custom alert media from third-party services
- PiP as a background execution mechanism
- Apple Watch or Live Activity companion surfaces
- Android support

## 7. Reference Links

- Twitch EventSub WebSockets: https://dev.twitch.tv/docs/eventsub/handling-websocket-events/
- Twitch EventSub subscription types: https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/
- Twitch CLI WebSocket event testing: https://dev.twitch.tv/docs/cli/websocket-event-command/
- Apple remote notification payloads: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CreatingtheNotificationPayload.html
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
