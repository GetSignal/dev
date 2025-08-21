# Feed Controller Skeletons

These controllers show how to integrate **PlayerPool**, the **preload policy**, and **telemetry**:

- `FeedViewController.swift` (iOS, UIKit) — attaches AVPlayerKit to a full-screen view, handles swipe up/down, promotes the preloaded player, and emits `view_end` (dwell + percent complete).
- `FeedFragment.kt` (Android) — binds ExoPlayer to PlayerView, handles swipe gestures, preloads the next clip, emits `view_end`.

**Wire your EventBus** to the real `/event` API (API Gateway → Kinesis) to feed ranking and analytics.
