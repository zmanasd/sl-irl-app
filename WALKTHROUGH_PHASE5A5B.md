# Phase 5A/5B Implementation Walkthrough (Work So Far)

Date: 2026-03-15
Branch: codex/feature/phase-5a-5b-implementation

## Context
Phase 5A introduces a PiP + backend relay + APNs architecture to replace silent audio backgrounding. The goal is to keep alert delivery reliable while staying App Store compliant.

## Work Completed

### 1) New Settings + AppSettings persistence
- Added `pipEnabled` and `pushNotificationsEnabled` to `AppSettings`.
- Wired these flags into `SettingsVM` and `SettingsView`.
- Added a stable `relayUserId` to identify the device to the relay server.

### 2) PiP lifecycle scaffolding
- Added `PiPManager` with:
  - PiP support checks
  - Player + player layer setup
  - Start/stop lifecycle helpers
  - Placeholder video generation at runtime (cached MP4 in app caches)
  - Non-blank PiP frames with simple branding text + status line
  - Status refreshes when queue count or connection state changes
- `IRLAlertApp` now:
  - Prepares PiP on entering main flow
  - Starts PiP when app enters background (if enabled)
  - Stops PiP when app returns to foreground

### 3) Push notification plumbing
- Added `PushNotificationManager` to:
  - Request authorization
  - Register/unregister APNs
  - Parse alert payloads into `AlertEvent`
  - Route alerts into `AlertQueueManager` + `EventStore`
- Added `AppDelegate` to receive APNs token + payloads
- On APNs token receipt, the app now registers with the relay server (when push is enabled).

### 4) PiP status view placeholder
- Added a minimal `PiPStatusView` SwiftUI component for future PiP overlay rendering.

### 5) Relay server scaffold
- Added `relay-server/` with:
  - `POST /register` for device token + services
  - `POST /presence` for direct-connection state
  - `GET /health`
  - WebSocket admin stub

### 6) Relay client + presence signaling (in progress)
- Added `RelayClient` for `/register` + `/presence` calls.
- Foreground/background changes now update relay presence:
  - Foreground and PiP-active background signal direct connection active
  - Background without PiP signals relay fallback
- PiP start/stop now updates relay presence as well.
- Relay registration now includes saved service credentials (when available).

### 7) Notification Service Extension scaffolding
- Added `IRLAlertNotificationService` target sources + Info.plist.
- Basic `NotificationService` implementation that can download a sound and attach it.
  - Sets notification title/body when alert payload includes user/type.

### 8) APNs entitlements + server send path
- Added app entitlements (`aps-environment`).
- Added `/alert` endpoint and APNs sender utility in relay server.
- Updated background modes to include `picture-in-picture`.

### 9) Streamlabs relay connector (initial)
- Added relay-side Streamlabs connector using Socket.IO.
- Connector forwards alerts via APNs when direct connection is inactive.

### 10) StreamElements relay connector (initial)
- Added relay-side StreamElements connector using Astro websocket.
- Connector forwards alerts via APNs when direct connection is inactive.

### 11) Twitch relay connector (initial)
- Added relay-side Twitch EventSub websocket connector.
- Creates EventSub subscriptions for follow, subscribe, cheer, and raid.

### 12) SoundAlerts manual webhook bridge (interim)
- Added `/soundalerts/webhook` endpoint to forward alert payloads via APNs.
- Added a relay test script to trigger `/alert` for end-to-end verification.

### 13) Onboarding opt-in step
- Added onboarding toggles for Push Alerts and Picture-in-Picture.

## Files Touched
- IRLAlert/IRLAlert/IRLAlertApp.swift
- IRLAlert/IRLAlert/Models/AppSettings.swift
- IRLAlert/IRLAlert/ViewModels/SettingsVM.swift
- IRLAlert/IRLAlert/Views/SettingsView.swift
- IRLAlert/IRLAlert/Services/PiPManager.swift
- IRLAlert/IRLAlert/Services/PushNotificationManager.swift
- IRLAlert/IRLAlert/Services/AlertQueueManager.swift
- IRLAlert/IRLAlert/Services/RelayClient.swift
- IRLAlert/IRLAlert/AppDelegate.swift
- IRLAlert/IRLAlert/Views/PiPStatusView.swift
- IRLAlert/IRLAlert/IRLAlert.entitlements
- IRLAlert/IRLAlertNotificationService/NotificationService.swift
- IRLAlert/IRLAlertNotificationService/Info.plist
- IRLAlert/IRLAlert/Views/OnboardingView.swift
- IRLAlert/project.yml
- IRLAlert/IRLAlert.xcodeproj/project.pbxproj
- relay-server/src/apns.js
- relay-server/src/connectors/manager.js
- relay-server/src/connectors/streamlabs.js
- relay-server/src/connectors/streamelements.js
- relay-server/src/connectors/twitch.js
- relay-server/scripts/send-test-alert.js
- relay-server/src/index.js
- relay-server/src/registry.js
- relay-server/README.md
- relay-server/package.json
- relay-server/.env.example

## Known Gaps / Next Steps
1. Configure APNs credentials and validate `/alert` end-to-end delivery.
2. Refine PiP visuals with a richer rendered view (beyond the placeholder video).

## Notes
- `SilentAudioPlayer` is no longer started on app launch, but the file still exists in the project. It may be removed later once PiP is confirmed stable.
- Push payload parsing uses a flexible schema with fallbacks to avoid drops during early integration.
