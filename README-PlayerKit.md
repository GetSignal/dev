# PlayerKit Skeletons (Swift + Kotlin)

This folder contains **thin wrappers** around the native video engines (AVPlayer on iOS, ExoPlayer on Android) with:
- **Player pooling** (2–3 instances) for smooth swipes,
- **Preload policy**: fully buffer current + ~**5–8 s** of the next item,
- **Telemetry hooks** that batch to your **event bus** (`/event` API → Kinesis).

## Files
- `PlayerKit-iOS.swift` — Swift 5+, iOS 14+. Contains `EventBus`, `AVPlayerKit`, and `PlayerPool`.
- `PlayerKit-Android.kt` — Kotlin + ExoPlayer 2.19+. Contains `EventBus`, `ExoPlayerKit`, and `PlayerPool`.

## Wiring to UI
- Bind `AVPlayerLayer` (iOS) or `PlayerView` (Android) to the **current** player instance from the pool.
- On swipe:
  1. Emit `view_end` for old item (include dwell and completion%),
  2. Promote **next → current** (already prepared),
  3. Ask pool to `preloadNext(url)` for the new next item.

## Event Bus
The provided `HttpEventBus` sends batched JSON to your `/event` API every ~3 s or when `flushNow()` is called. Replace with your networking stack or hook into your existing analytics pipeline.

**Event examples**
- `prepared`, `playback_start`, `first_frame { ms }`
- `rebuffer_start`, `rebuffer_end`, `bitrate_change { bitrate, height }`
- `seek { ms }`, `ended`, `paused`
- `playback_progress { position_s }`
- `preload_started { url }`

## Notes & TODOs
- The **5–8 s preload** is a *policy hint*: buffering is ultimately device/network dependent. It’s still effective to reduce TTFB between swipes.
- Add **view definitions** (e.g., `view = ≥2 s OR ≥50% watched`) in your feed controller and emit a `view_end` summary.
- If first-frame > 1.5 s or two early re-buffers, **downshift** the session (cap bitrate to 540p) and emit an event; reset next app launch.

---

Drop these files into your iOS/Android projects, inject your API base URL in `HttpEventBus`, and wire the pool into your feed view controller/fragment.
