# Ticket 27 — Clients: UI — Create Button (+) in Main Menu Bar

**Date:** 2025-09-08  
**Priority:** P2 (core entry to creation)  
**OS Baselines:** iOS **16+**; Android **minSdk 26** / **targetSdk 35**

## PURPOSE
Add a prominent **Create** button (plus **+** icon) centered in the **Main Menu Bar** that opens the creation flow for recording or uploading videos.

## SCOPE (V1 — entry & routing only)
- **UI:** Centered primary button in the bottom bar (raised/突出视觉效果). Uses platform-consistent iconography.  
- **Tap Behavior:** Present a **Create chooser** with two options:
  1. **Record** — opens in-app camera capture (video).  
  2. **Upload** — opens device/library picker (photos/videos) and supported cloud pickers (where available).
- **Routing:** After selection, route to the existing **Uploader/Editor** entry screen (stub acceptable) without kicking off network requests until the user confirms.
- **Permissions:** Request camera/microphone/storage permissions just-in-time (first use). Handle deny/defer gracefully.
- **Design/Accessibility:** Respects safe areas and bottom gestures; focusable; labeled “Create” for screen readers.
- **No Telemetry Additions:** Reuse existing EventBus if needed; no new event types required in V1.

## NON-GOALS (deferred)
- Full camera pipeline (exposure/filters, multi-clip editing).  
- Drafts, background uploads, or redemption flows.  
- Server-side rewards or incentives for creation.

## ACCEPTANCE CRITERIA
- A centered **+** button appears in the Main Menu Bar and is tappable on all supported devices.  
- Tap → shows **Record** / **Upload** chooser; chooser cancel returns to previous state.  
- **Record** launches camera capture UI; **Upload** launches system picker (and cloud pickers where available).  
- On selection, user is routed to the uploader/editor entry screen (no upload started yet).  
- No regression to feed playback performance or tab navigation.  
- Light/Dark snapshots and dynamic type pass; TalkBack/VoiceOver reads correct labels.

## IMPLEMENTATION NOTES
- **iOS:** Custom `UITabBar` center button (or SwiftUI `TabView` overlay). Create `CreateChooserViewController` (sheet). For camera, use `AVCaptureSession` stub screen; for upload, present `PHPickerViewController` (video-only).  
- **Android:** BottomNavigation with centered **FAB** (`androidx.compose.material3` or View-based). Show a modal bottom sheet chooser. For camera, route to a capture stub using `CameraX` VideoCapture; for upload, use `ACTION_OPEN_DOCUMENT` (video-only) with persisted URI permissions.  
- Ensure button notches/overlaps are handled on devices with gesture nav and various insets.

## DEPENDENCIES
- **20 — Mobile Bulk Uploader (iOS & Android):** destination after choosing media/recording.  
- **21 — Mobile Cloud Drive Pickers:** enable cloud providers in “Upload” path where applicable.  
- **22 — Upload Session API Preflight:** invoked by the uploader once user confirms details/meta.  
- **23 — Ingest Status Dashboard — Mobile Views:** surfaced after submission (out-of-scope for this button).

## ROLLOUT
- Feature flag: `ff_create_button` (default OFF). Enable in canary before broad release.

