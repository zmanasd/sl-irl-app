# Phase 5A/5B Implementation Walkthrough (Work So Far)

Date: 2026-03-20
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
- Added deferred PiP start queueing so start attempts wait for `isPictureInPicturePossible` instead of hard-failing on early host timing.
- Reduced startup race conditions by removing eager PiP prepare calls from audio-engine startup; host attachment now drives preparation.
- This keeps the current placeholder media for now, but changes the playback surface toward a more AVKit-native architecture.

### 20) Step 1 + Step 2 pivot implementation started
- Added a baseline PiP playback mode that uses real media (`AVPlayerItem`) instead of regenerated placeholder status frames in Debug builds.
- Updated the app UI hosting path so baseline mode uses a visible full-window inline `AVPlayerViewController` host for PiP eligibility testing.
- Enforced strict startup order in `PiPManager`: audio session activation happens before controller setup/start attempts.
- Moved `PiPManager` toward a single-controller lifetime policy:
  - create once when the first stable layer is discovered
  - do not rebind/recreate the PiP controller when later layer instances appear
- Added stability gating for initial controller binding so PiP controller creation is deferred until the hosted layer is attached in-window with non-zero bounds.

### 21) Step 1/2 follow-up diagnostics and startup hardening
- Relaxed PiP layer stability gating to require only:
  - layer attached in hierarchy
  - non-zero layer bounds
- Added granular stability diagnostics in `PiPManager` debug state:
  - `hier` (bound layer has superlayer)
  - `size` (bound layer bounds are non-zero)
  - `hostWin` (host view attached to a `UIWindow`)
- Expanded `PiP not possible yet` failure text with these sub-signals.
- Updated baseline host/controller defaults to be AVKit-friendly:
  - enable playback controls in baseline mode
  - enable now-playing updates in baseline mode
  - keep placeholder-only settings (`requiresLinearPlayback = false`, fill gravity) on placeholder path.
- Updated debug overlay to always show `attempt`, `pending`, and `last` lines (including `none`) to avoid hidden-state ambiguity during testing.
- Added scene-phase fallback start on `.background` (in addition to `.inactive`) so non-deterministic transition timing still triggers a PiP start attempt in baseline diagnostics mode.

### 22) Baseline host path switched to direct AVPlayerLayer
- In baseline diagnostics mode, switched host rendering from embedded `AVPlayerViewController` to a direct `AVPlayerLayer` host view.
- This removes AVKit internal-layer discovery ambiguity so the PiP controller binds to the exact layer rendered inline.
- Updated host-attachment debug signal to treat either:
  - `AVPlayerViewController` window attachment, or
  - direct `AVPlayerLayer` hierarchy attachment
  as `hostWin: yes`.
- Cleared stale “host not ready” failure text once the layer host is attached and controller binding proceeds.

### 23) Baseline host persistence and 16:9 eligibility probe
- Kept the baseline debug host attached across scene transitions even when app-level PiP toggle is off, so background diagnostics stay valid in baseline mode.
- Changed baseline inline host surface to a fixed 16:9 presentation to probe known wide-layer PiP eligibility issues.
- Added bound-layer aspect-ratio diagnostics:
  - `aspect` line in debug overlay
  - `aspect` included in `PiP not possible yet (...)` failure string.

### 24) PiP compatibility hardening follow-up
- Updated baseline inline host layout to device-width 16:9 instead of capped-card sizing to match stricter historical PiP eligibility behavior.
- Switched PiP controller creation to the newer `AVPictureInPictureController.ContentSource(playerLayer:)` path (with fallback) when available.
- Added a dedicated baseline audio-session profile:
  - category `.playback`
  - mode `.moviePlayback`
  - no mix/duck options
  to remove audio-session policy as an eligibility variable during baseline diagnostics.

### 25) ContentSource diagnostics correction
- Updated layer-stability/aspect diagnostics to use the explicitly bound source layer reference, not `pipController.playerLayer`.
- This avoids false `hier:no / size:no / aspect:missing` debug reports after switching to `ContentSource`.
- Removed baseline host clipping/masking chrome so the inline `AVPlayerLayer` remains an unmasked rectangular video surface during eligibility checks.

### 26) AVKit-host eligibility A/B fallback
- Switched baseline inline host back to `AVPlayerViewController` (still 16:9) to probe whether iOS 26 PiP eligibility requires an AVKit-managed playback surface.
- Re-enabled host view interaction for baseline host path during diagnostics to avoid potential eligibility rejection on non-interactive playback surfaces.

### 27) Media-source and track diagnostics expansion
- Added baseline source diagnostics and fallback ordering:
  - bundled clip
  - generated local fallback
  - remote MP4
  - remote HLS
- Added debug state for:
  - `source`
  - `video` (video track presence)
  - `pres` (presentation size)

### 28) Reactive PiP start refactor
- Reworked PiP start flow toward reactive eligibility:
  - queue start intent
  - observe `isPictureInPicturePossible`
  - attempt start when eligibility flips asynchronously
- Added layer bounds observation and re-evaluation hooks so controller binding can recover from early `0x0` layout states.
- Reasserted baseline audio session profile at start attempt time.

### 29) Forced-start diagnostic path
- Added explicit forced PiP invocation path from debug control.
- Added diagnostics for:
  - force arm state
  - last delegate event
  - no-callback timeout path (`force-no-callback`)
- Preserved force context across inactive/background transitions so auto retries do not mask force-attempt telemetry.
- Restricted forced start invocation to active app state and auto-retry on readiness while active.

### 30) Current highest-confidence finding
- On physical device, app reaches a fully healthy playback state:
  - `ctrl: yes(legacy-player-layer)`
  - `stable: yes`
  - `video: yes`
  - `pres: 1280x720`
  - `audio active: yes (playback/moviePlayback)`
- Yet PiP remains `possible: no`, and forced `startPictureInPicture()` can yield:
  - `delegate: force-no-callback`
  - `last: Force start invoked; AVKit returned no start/fail callback (possible:no)`
- Lock-screen media controls appear for app playback, confirming the playback session is active.

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
2. Do not continue broad placeholder/media tuning as the primary PiP lever.
3. Validate whether this is app-context/system policy behavior by reproducing PiP in a minimal standalone AVKit sample on the same iOS/device.
4. Pivot Phase 5A investigation toward a different architecture:
   - a more AVKit-native playback/PiP path, or
   - a different background strategy if the true requirement is persistent alert monitoring rather than media playback.
5. Revisit cleanup of legacy silent-audio code once the replacement direction is chosen.

## Notes
- During debugging, `SilentAudioPlayer` was temporarily reintroduced into the PiP startup path to test whether AVKit required a stronger active background playback configuration.
- Push payload parsing uses a flexible schema with fallbacks to avoid drops during early integration.
- The current branch contains substantial PiP diagnostics intended to support the next implementation angle, not just the current placeholder-media experiment.
