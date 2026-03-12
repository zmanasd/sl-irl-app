# Product Requirements Document (PRD): Enhanced IRL Alert App

## 1. Overview
The Enhanced IRL Alert App is a background-capable alert relay application designed specifically for In-Real-Life (IRL) streamers. Its primary purpose is to ensure that streamers reliably hear and see their stream alerts (donations, follows, subscriptions, hosts, raids, etc.) while streaming from their mobile devices, without interrupting their primary streaming software.

## 2. Problem Statement
The current prototype (`sl-irl-bridge`) relies on a browser-based WebSocket connection to receive alerts. On mobile platforms, specifically Apple (iOS) devices, web browsers are placed into a stasis/suspended state when minimized to conserve battery. This inherently breaks WebSocket connections and pauses audio playback, causing IRL streamers to miss essential alerts when their primary streaming application (e.g., IRL Pro, Twitch App) is active on screen.

## 3. Target Audience & Use Case
**Target Audience:** IRL Streamers that stream from mobile devices (specifically iPhones) and require a reliable alert relay that runs silently in the background.

**Primary Use Case:** A streamer goes live using a mobile streaming app. They run this Enhanced Alert App in the background. As viewers interact with the stream (subscribing, donating, etc.), the streamer hears the alert audio and text-to-speech (TTS) natively mixed with their device audio, ensuring they never miss an interaction even when reading chat from their primary app.

## 4. Core Objectives & Requirements

1. **A Working Alerts System:** The app must reliably receive and process alerts from major streaming services (Streamlabs, StreamElements, SoundAlerts, Twitch Native Alerts).
2. **Plays Alerts Continuously in the Background:** The application must maintain network connections and play audio even when the app is minimized or the device screen is locked, successfully mixing audio over the primary mobile streaming app without interrupting it.
3. **Pulls the Full Alert:** The app must fetch and display/play the complete alert payload from the chosen alert service, including any custom sounds, text, or TTS configured by the user.

### 4.1. Supported Alert Types (MVP)
At minimum, the following event types must be supported across all connected services:
- **Donations / Tips**
- **Follows**
- **Subscriptions** (new, resub, gifted, mystery/bomb gifts)
- **Bits / Cheers**
- **Hosts**
- **Raids**

Additional service-specific types (e.g., SoundAlerts custom sound redemptions, Twitch channel point redeems) may be added post-MVP.

### 4.2. Connection Methods
To maximize flexibility while keeping the alerts functioning in the background, users must be provided with two distinct connection methods:

1. **Browser Source URL (Pass-through):** Users can paste their unique Browser Source overlay URL. The app will load this source internally and intercept/play the audio events automatically.

   > **⚠️ iOS Technical Caveat:** On iOS, a `WKWebView` is subject to the same background suspension as Safari. Therefore, the app **cannot** rely on the web view itself staying alive in the background. The implementation must use native-layer workarounds, such as:
   > - Intercepting WebSocket traffic at the native networking layer (e.g., `URLSessionWebSocketTask`) while parsing the overlay URL to extract the socket token/endpoint.
   > - Maintaining a silent audio track on the `AVAudioSession` to keep the app process active and prevent OS suspension.
   > - Using the web view only for initial connection setup / token extraction, then handing off to a native socket connection.

2. **Direct Service Authentication (OAuth):** Users can securely sign in to their respective alert service via OAuth. The app will directly consume the service's API/WebSockets, generating its own native Text-to-Speech (TTS) and triggering alert sound files manually.

### 4.3. Alert Queuing & Concurrency
When multiple alerts fire in quick succession (e.g., a raid followed by a flood of subs):
- Alerts must be **queued and played sequentially** — one at a time, in the order received.
- A short configurable delay (default ~1 second) is inserted between consecutive alerts to prevent audio overlap.
- If the queue grows excessively large (e.g., 20+ pending), older alerts beyond a threshold should be summarized or silently logged to prevent an extended playback backlog.

### 4.4. Alert Processing & Presentation
- **Visual Event Log:** When the app is in the foreground, it should display a clean, readable feed of recent alert events so the streamer can review missed interactive moments.
- **Audio Output:** Play any associated media/sound files provided by the alert service natively.
- **Text-to-Speech (TTS):** Utilize device-native text-to-speech to synthesize alert messages (e.g., "JohnDoe just subscribed for 5 months").

### 4.5. User Settings
The app must provide the following configurable options:
- **Alert Volume:** Independent volume slider for alert sounds and TTS, separate from the device master volume.
- **TTS Toggle:** Enable or disable text-to-speech globally.
- **TTS Voice Selection:** Allow the user to pick from available system voices.
- **Alert Type Filters:** Toggle which alert types trigger audio (e.g., disable follow alerts but keep donations).
- **Queue Overflow Threshold:** Configure the maximum queue size before summarization kicks in.

### 4.6. Reconnection & Reliability
IRL streaming frequently involves unreliable mobile data connections. The app must:
- **Auto-Reconnect:** Automatically re-establish connections when the network drops, using exponential backoff (e.g., 1s → 2s → 4s → … → max 30s).
- **Connection Status Indicator:** Display a persistent, at-a-glance indicator (e.g., green dot / red dot) showing the health of each connected alert service.
- **Offline Queuing:** If the connection drops mid-stream and is restored, any alerts that were missed during the outage should be fetched retroactively if the service API supports it.
- **Notification on Disconnect:** Optionally send an iOS notification if the alert connection has been down for more than a configurable duration (default 30 seconds), so the streamer is aware.

## 5. Technical Approach & Constraints

### 5.1. Platform Architecture
- **Decision:** The project will be developed as a Native iOS app using **Swift / SwiftUI**.
- **Rationale:** The core requirement of maintaining active WebSocket connections and uninterrupted audio mixing in the background is rigorously restricted by iOS. Cross-platform frameworks like React Native or Flutter frequently experience background thread suspension (meaning their JavaScript/Dart runtimes are paused by the OS) unless carefully bridged to custom native modules. Since the MVP is exclusively iOS-focused, building natively in Swift provides direct, unhindered access to `AVAudioSession` and Apple's background execution APIs without the liability of maintaining complex native bridges.
- A Progressive Web App (PWA) or simple web page will **not** fulfill the strict iOS background execution requirements.

### 5.2. Audio Session Management (iOS specifics)
- The app must configure its `AVAudioSession` with category `.playback` and option `.mixWithOthers`. This ensures the OS allows the app's sounds to play seamlessly over the primary streaming app without taking exclusive ownership of the audio hardware.
- A silent audio loop may be required to keep the app's audio session active and prevent iOS from suspending the process during idle periods between alerts.

## 6. Out of Scope for MVP (V1)
- **Android support** — iOS is the primary target; Android may follow in a future version.
- **On-screen overlay rendering** — This app is an audio companion, not a visual overlay on the camera/stream feed.
- Custom CSS injection/editing for Browser Source URLs directly in-app.
- Video streaming capabilities (this app operates strictly as an alert relayer companion).
- Custom alert media uploads.
- Advanced wearable integrations (e.g., Apple Watch companion app).
