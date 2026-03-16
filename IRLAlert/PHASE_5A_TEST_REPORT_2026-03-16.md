# Phase 5A Test Report

Date: March 16, 2026
Branch: `codex/fix-xcode-build-errors`
App: `IRLAlert`
Focus: Phase 5A Picture-in-Picture (PiP), background execution, and related build/test readiness

## Summary

Phase 5A testing made meaningful progress on build stability, local device deployment, and PiP source instrumentation, but PiP itself is still not entering an active state on either Simulator or physical iPhone testing.

The strongest current conclusion is that the existing "fake media" PiP strategy remains ineligible in AVKit, even after:

- visible inline preview hosting
- background audio session activation
- silent audio loop startup
- silent audio track addition to the placeholder asset
- PiP controller rebinding to the visible layer
- full-window PiP source view changes

At the end of testing, the app consistently reached a state where playback was:

- `supported: yes`
- `ready: yes`
- `item: ready`
- `time: playing`

but PiP still remained:

- `possible: no`

## Test Objectives

The Phase 5A testing pass aimed to verify:

1. The app builds cleanly in Xcode and on the command line.
2. The app installs and runs on Simulator and physical iPhone hardware.
3. PiP preview content is present in the view hierarchy.
4. PiP starts when the app backgrounds.
5. Background audio / playback configuration is sufficient to keep PiP eligible.

## Build And Environment Readiness

### Resolved Before Or During Testing

- Swift 6 / concurrency build errors were fixed in the app code.
- The missing `SocketIO` package issue in Xcode was resolved.
- The app was pulled onto the active branch and tested from the same project/worktree to avoid stale-build confusion.
- A debug PiP badge and debug preview card were added to verify runtime state on-device.

### Device Signing Constraints

- Personal Team signing could not support Push Notifications capability for local on-device testing.
- Push-related signing blockers were worked around so the app could be run locally for PiP testing.
- Command-line device builds were unreliable due local Xcode account/provisioning visibility, so final on-device execution was primarily driven from the Xcode UI.

## Test Matrix

### 1. iPhone Simulator: iPhone 16e (iOS 26.3.1)

Result: Failed due simulator limitation

Observed:

- PiP preview path was exercised.
- Logs reported `PiP not supported on this device.`

Conclusion:

- This simulator could not be used to validate PiP.

### 2. iPhone Simulator: iPhone 17 (iOS 26.3.1)

Result: Failed due simulator limitation

Observed:

- App launched successfully.
- Logs again reported `PiP not supported on this device.`

Conclusion:

- iPhone simulator testing was not a reliable path for PiP validation.

### 3. iPad Simulator: iPad Pro 11-inch (M5) (iOS 26.3.1)

Result: Failed to start PiP

Observed:

- PiP was attempted repeatedly after several code fixes.
- Logs reported `PiP failed to start: Failed to start picture in picture.`
- A temporary iPad-compatible build override (`TARGETED_DEVICE_FAMILY=1,2`) was also tested.

Conclusion:

- Even with iPad-compatible build settings, PiP could not be validated reliably in this simulator environment.

### 4. Physical Device: iPhone 12 Pro (iOS 26.0.1)

Result: App deployment succeeded; PiP eligibility remained false

Observed:

- The app eventually installed and launched successfully from Xcode.
- The correct branch/build was confirmed after earlier stale-branch confusion.
- The debug badge and PiP preview were visible on-device.
- On backgrounding the app, the preview disappeared and PiP did not appear.
- Manual debug forcing of PiP also did not result in active PiP.

Final observed on-device state:

- `enabled: on`
- `supported: yes`
- `possible: no`
- `flow: main`
- `layer: yes`
- `active: no`
- `ready: yes`
- `item: ready`
- `time: playing`
- `attempt: debug button`
- After background/return: `last: PiP not possible yet`

Conclusion:

- The current media/player configuration is still not becoming PiP-eligible in AVKit on real hardware.

## Runtime Fixes Attempted During Testing

The following implementation changes were tested over the course of Phase 5A validation:

- Recreated the PiP controller after placeholder video generation completed.
- Added a visible inline PiP host view so the `AVPlayerLayer` lived in the hierarchy.
- Shifted PiP startup timing to `.inactive` instead of waiting until `.background`.
- Added debug PiP UI overlays showing build/runtime state.
- Added a visible PiP preview card.
- Added explicit `canStartPictureInPictureAutomaticallyFromInline`.
- Added `requiresLinearPlayback = false`.
- Added debug controls to attempt manual PiP start.
- Added readiness diagnostics for:
  - PiP support
  - PiP possibility
  - layer attachment
  - player readiness
  - player item status
  - time control status
- Started the silent audio loop alongside the audio session.
- Changed the generated placeholder asset from video-only to audio+video.
- Versioned the placeholder filename to prevent stale cached media reuse.
- Rebound the PiP controller after the visible layer attached.
- Moved the real PiP host to a full-window background while leaving the preview card as UI.

## Verified Successes

These outcomes were successfully verified:

- The branch builds successfully via command-line Xcode build.
- The app runs on a physical iPhone.
- The debug PiP state is visible and trustworthy enough for runtime inspection.
- The preview/player layer can be attached and made `ready`.
- The player item reaches `ready` state.
- The player enters `playing` state.

## Remaining Failure

The unresolved failure is:

- AVKit never transitions the current setup into a PiP-possible state.

This remained true even after:

- physical device testing
- valid playback state
- visible source layer
- silent audio track addition
- full-window source-host experiment

## Current Working Hypothesis

The most likely explanation is that the current PiP strategy is fundamentally misaligned with what AVKit expects for media PiP on iPhone.

In practical terms, the app is currently trying to drive PiP using synthetic placeholder media and a custom hosted playback surface. Testing suggests AVKit still does not consider that setup eligible, even when the player is technically ready and active.

## Recommendation For The Next Angle

Do not continue iterating on the current placeholder-media PiP path as the primary approach.

Recommended next step:

1. Pivot to a different PiP architecture instead of further tuning the fake-media approach.
2. Re-evaluate whether the feature should use:
   - a more AVKit-native media playback path, or
   - a different background strategy altogether if the product goal is persistent alert monitoring rather than true media playback.
3. Treat the current implementation as a useful diagnostic branch, not yet a validated production solution.

## Confidence Level

Confidence in the findings: Medium-high

Reason:

- Multiple environments were tested.
- Physical hardware was tested.
- The failure is consistent across repeated attempts.
- Debug instrumentation now provides reliable runtime visibility into the player/PiP state.

