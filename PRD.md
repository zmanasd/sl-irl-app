# Product Requirements Document: IRL Alert App - Twitch-First MVP

## 1. Overview

IRL Alert is an iOS companion app for mobile IRL streamers who need reliable awareness of Twitch stream interactions while using another mobile streaming app.

The MVP proves one core concept:

**Twitch EventSub -> relay server -> APNs -> iPhone alert receipt -> foreground queue/log/audio**

The app is not trying to reproduce every third-party alert provider at MVP. It first proves that Twitch-native events can be received server-side, delivered to an iPhone through push notifications, reviewed in the app, and played through native audio/TTS when the app is active.

## 2. Problem Statement

Mobile browsers and many app processes are suspended by iOS when backgrounded. A browser-based alert bridge can lose WebSocket connectivity or pause audio playback when the streamer switches to Moblin, the Twitch app, or another streaming tool.

Previous planning attempted to solve this with silent audio, PiP, direct service sockets, and multiple third-party alert services in one MVP. That created too much platform risk before the basic product loop had been proven.

The reset MVP focuses on a narrower proof: keep alert listening server-side using Twitch EventSub and deliver mobile awareness through APNs, with strong diagnostics so failures can be located rather than guessed at.

## 3. Target Audience And Use Case

**Target audience:** iPhone-based IRL streamers who stream through mobile tools and need reliable Twitch interaction alerts while another app is foregrounded or the phone is locked.

**Primary use case:** A streamer signs in with Twitch, enables notifications, starts an IRL stream in their preferred streaming app, and receives audible iOS notifications for Twitch follows, subscriptions, cheers, and raids. When they return to IRL Alert, they can review received events and, while the app is foregrounded, hear native alert audio and TTS through the app queue.

## 4. MVP Objectives

1. **Twitch-native alert delivery:** Receive supported Twitch EventSub events through a backend relay.
2. **Background awareness through APNs:** Send visible, audible push notifications to the iPhone when Twitch events arrive.
3. **Foreground queue and playback:** When the app is active, route alert payloads into the existing FIFO queue, event log, native audio, and TTS flow.
4. **Real-device diagnostics:** Provide enough app and relay diagnostics to identify where delivery failed.
5. **Proof-gated implementation:** Do not depend on platform behavior that has not passed an isolated proof harness.

## 5. Supported Alert Types For MVP

MVP supports Twitch-native events only:

- Follows
- Subscriptions
- Resubscriptions
- Gift subscriptions
- Bits / cheers
- Raids
- Optional: channel point redemptions, if Twitch scopes and EventSub testing are completed without delaying the core proof

The MVP does not include donations/tips because those require third-party provider integrations such as Streamlabs, StreamElements, or another payment/donation service.

## 6. Connection Method

### 6.1 Twitch OAuth

Users connect Twitch through OAuth. The relay server stores and refreshes Twitch tokens server-side. The app must not store long-lived Twitch access or refresh tokens locally for MVP.

### 6.2 Relay Device Registration

After APNs registration, the app sends its device token and app user identifier to the relay. The relay uses this registration to send APNs alerts for normalized Twitch events.

### 6.3 Out-Of-Scope MVP Connection Methods

The MVP does not support:

- Browser Source URL parsing
- Streamlabs socket tokens
- StreamElements tokens
- SoundAlerts webhooks or sockets
- Direct iOS WebSocket listening as the background delivery mechanism

## 7. Alert Processing And Presentation

### 7.1 Background / Locked / Terminated

When the app is backgrounded, locked, or terminated, the MVP delivery path is a visible APNs notification with sound. The app does not promise continuous in-process audio playback in these states.

### 7.2 Foreground

When the app is active:

- Incoming alert payloads are deduped.
- Alerts are persisted to the event log.
- Alerts enter the FIFO queue.
- Native audio and TTS play sequentially.

### 7.3 Queue Behavior

When multiple alerts arrive quickly:

- Alerts are queued and processed in received order.
- A configurable inter-alert delay defaults to about 1 second.
- If the queue exceeds the configured threshold, excess alerts are skipped or summarized rather than creating an unusable backlog.

## 8. User Settings

MVP settings should include:

- Twitch connection status
- Push notification permission/status
- Relay registration status
- Alert volume for foreground playback
- TTS enable/disable for foreground playback
- TTS voice/rate where already supported
- Alert type filters for supported Twitch event types
- Queue overflow threshold
- Diagnostics/export access

PiP settings and silent-audio controls are not part of the MVP user-facing experience.

## 9. Reliability And Diagnostics

The MVP must avoid blind platform testing. Every alert should be traceable through a correlation chain:

```text
twitch_message_id -> relay_event_id -> apns_id -> ios_received_id -> queue_event_id -> playback_event_id
```

The app must expose diagnostics for:

- Notification permission state
- APNs token registration timestamp
- Relay registration status
- Last received notification correlation ID
- Last queued alert correlation ID
- Last audio/TTS playback state
- Current audio route/category

The relay must expose diagnostics for:

- Twitch EventSub session state
- Subscription status
- Last keepalive timestamp
- Reconnect count
- OAuth token refresh state
- Last normalized alert
- Last APNs send result
- APNs response ID where available

## 10. Technical Approach

### 10.1 Platform

- Native iOS app using Swift and SwiftUI
- Node.js backend relay server
- Twitch EventSub WebSocket for MVP event ingestion
- APNs for mobile background/locked/terminated alert delivery
- Native app queue, event log, audio, and TTS for foreground playback

### 10.2 Background Strategy

iOS may suspend ordinary app execution after backgrounding. Silent audio loops are not acceptable as a shipping strategy, and prior PiP experiments did not become reliable enough to remain on the MVP critical path.

Therefore:

- The relay keeps Twitch EventSub connections alive.
- APNs provides background/locked/terminated user awareness.
- The app handles rich queue/audio/TTS behavior when active.
- PiP remains a post-MVP research topic unless a separate Apple-compliant proof passes independently.

### 10.3 Anti-Guesswork Requirement

No platform-sensitive capability may enter the production MVP path until it has passed:

- An isolated proof harness
- Observable logs
- Correlation IDs
- Pass/fail criteria
- A documented kill or pivot rule

## 11. Out Of Scope For MVP

- Streamlabs integration
- StreamElements integration
- SoundAlerts integration
- Donations/tips
- Browser Source URL parsing
- Custom third-party alert sounds/media
- PiP background execution
- Silent audio background execution
- Android support
- Apple Watch or Live Activity companion surfaces
- On-stream visual overlays
- Video streaming features

## 12. MVP Acceptance Criteria

The MVP is accepted when:

- A user can connect Twitch.
- The app can register for APNs and relay delivery.
- Twitch mock or real events reach the relay and normalize correctly.
- A physical iPhone receives audible APNs notifications while backgrounded or locked.
- Foreground notifications route into the queue, event log, audio, and TTS once.
- Reconnect and duplicate-delivery tests do not create duplicate queue entries.
- Diagnostics can identify whether a failed alert stopped at Twitch, relay, APNs, iOS receipt, queue, or playback.
