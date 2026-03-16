# Phase 5A/5B Implementation Walkthrough (Work So Far)

Date: 2026-03-16
Branch: codex/fix-xcode-build-errors

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

### 14) Xcode and device-build stabilization
- Fixed Swift 6 / concurrency build errors that were blocking local Xcode builds.
- Resolved the missing `SocketIO` package issue in Xcode.
- Cleaned branch usage so the active Xcode project and the edited worktree matched.
- Added `.gitignore` coverage for generated `relay-server/node_modules/`.

### 15) On-device PiP diagnostics and runtime instrumentation
- Added a visible debug badge to the app showing:
  - PiP enabled state
  - support state
  - possibility state
  - player layer attachment
  - player readiness
  - player item readiness
  - time-control state
  - last PiP attempt / failure reason
- Added a visible PiP preview card for runtime confirmation.
- Added a manual debug control to force PiP start attempts while the app is foregrounded.

### 16) PiP runtime experiments completed
- Recreated the PiP controller after placeholder generation completed.
- Added an in-hierarchy `AVPlayerLayer` host view for PiP.
- Shifted PiP startup timing to the `.inactive` scene phase.
- Kept the PiP host attached during background transitions.
- Enabled `canStartPictureInPictureAutomaticallyFromInline`.
- Set `requiresLinearPlayback = false`.
- Started the silent audio loop alongside audio session setup during PiP testing.
- Added state observation for:
  - `isPictureInPicturePossible`
  - `isReadyForDisplay`
  - player item status
  - player time control status
- Changed the placeholder asset from video-only to audio+video.
- Versioned the placeholder filename to prevent stale cached media reuse.
- Rebound the PiP controller after the visible player layer attached.
- Moved the actual PiP source host to a full-window background while preserving a small preview card for UI/debugging.

### 17) Physical-device testing completed for current PiP approach
- Successfully deployed and ran the app on a physical iPhone 12 Pro (iOS 26.0.1).
- Confirmed the debug overlay and preview card were visible on-device.
- Confirmed the player entered a technically healthy playback state:
  - `supported: yes`
  - `ready: yes`
  - `item: ready`
  - `time: playing`
- PiP still never became eligible:
  - `possible: no`
- Manual foreground PiP start attempts did not succeed.
- Backgrounding the app still did not produce PiP.
- Returning to foreground showed the debug failure state:
  - `last: PiP not possible yet`

### 18) Test reporting
- Added a formal Phase 5A test report:
  - `IRLAlert/PHASE_5A_TEST_REPORT_2026-03-16.md`
- The report captures:
  - simulator outcomes
  - physical-device outcomes
  - implementation experiments attempted
  - current hypothesis and pivot recommendation

### 19) Pivot follow-up: AVKit-native host path (in progress)
- Switched PiP host rendering from a custom `UIView` + direct `AVPlayerLayer` path to an embedded `AVPlayerViewController` host.
- Added `PiPManager` support for attaching/reconfiguring a hosted `AVPlayerViewController`.
- Added runtime layer discovery/rebinding so PiP controller setup uses the AVKit-managed `AVPlayerLayer` when available.
- Preserved existing PiP diagnostics and expanded debug state to report hosted view-controller attachment.
- This keeps the current placeholder media for now, but changes the playback surface toward a more AVKit-native architecture.

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
- IRLAlert/PHASE_5A_TEST_REPORT_2026-03-16.md
- WALKTHROUGH_PHASE5A5B.md

## Known Gaps / Next Steps
1. Configure APNs credentials and validate `/alert` end-to-end delivery.
2. Do not continue iterating on the current placeholder-media PiP path as the primary approach.
3. Pivot Phase 5A investigation toward a different architecture:
   - a more AVKit-native playback/PiP path, or
   - a different background strategy if the true requirement is persistent alert monitoring rather than media playback.
4. Revisit cleanup of legacy silent-audio code once the replacement direction is chosen.

## Notes
- During debugging, `SilentAudioPlayer` was temporarily reintroduced into the PiP startup path to test whether AVKit required a stronger active background playback configuration.
- Push payload parsing uses a flexible schema with fallbacks to avoid drops during early integration.
- The current branch contains substantial PiP diagnostics intended to support the next implementation angle, not just the current placeholder-media experiment.
