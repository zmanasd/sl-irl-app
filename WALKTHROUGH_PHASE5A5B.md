# Phase 5A/5B Implementation Walkthrough (Work So Far)

Date: 2026-03-15
Branch: codex/feature/phase-5a-5b-implementation

## Context
Phase 5A introduces a PiP + backend relay + APNs architecture to replace silent audio backgrounding. The goal is to keep alert delivery reliable while staying App Store compliant.

## Work Completed

### 1) New Settings + AppSettings persistence
- Added `pipEnabled` and `pushNotificationsEnabled` to `AppSettings`.
- Wired these flags into `SettingsVM` and `SettingsView`.

### 2) PiP lifecycle scaffolding
- Added `PiPManager` with:
  - PiP support checks
  - Player + player layer setup
  - Start/stop lifecycle helpers
  - Placeholder video loop via `pip_placeholder.mp4` (not yet added to bundle)
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

### 4) PiP status view placeholder
- Added a minimal `PiPStatusView` SwiftUI component for future PiP overlay rendering.

### 5) Relay server scaffold
- Added `relay-server/` with:
  - `POST /register` for device token + services
  - `POST /presence` for direct-connection state
  - `GET /health`
  - WebSocket admin stub

## Files Touched
- IRLAlert/IRLAlert/IRLAlertApp.swift
- IRLAlert/IRLAlert/Models/AppSettings.swift
- IRLAlert/IRLAlert/ViewModels/SettingsVM.swift
- IRLAlert/IRLAlert/Views/SettingsView.swift
- IRLAlert/IRLAlert/Services/PiPManager.swift
- IRLAlert/IRLAlert/Services/PushNotificationManager.swift
- IRLAlert/IRLAlert/AppDelegate.swift
- IRLAlert/IRLAlert/Views/PiPStatusView.swift
- IRLAlert/IRLAlert.xcodeproj/project.pbxproj
- relay-server/*

## Known Gaps / Next Steps
1. Add a valid PiP video source:
   - Bundle `pip_placeholder.mp4` or replace with a real rendering pipeline.
2. Add Notification Service Extension target for rich alert payloads + custom sounds.
3. Add APNs entitlements, keys, and payload schema definition.
4. Implement iOS relay client (register device token, presence).
5. Implement relay server connectors + APNs send path.

## Notes
- `SilentAudioPlayer` is no longer started on app launch, but the file still exists in the project. It may be removed later once PiP is confirmed stable.
- Push payload parsing uses a flexible schema with fallbacks to avoid drops during early integration.
