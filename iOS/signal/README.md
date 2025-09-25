# Signal iOS — Runtime Flags and Debugging

## Runtime Flags (via Environment Variables / Launch Arguments)
These are read at runtime using `ProcessInfo.processInfo`.

- `API_BASE_URL` (Environment Variable)
  - Default: `https://api.example.com`
  - Used by `FeedViewModel` to call `/v1/feed` and `/v1/events`.

- `ENABLE_LONG_PRESS_SCRUB` (Environment Variable)
  - Default: `false`
  - Feature flag to enable long‑press storyboard scrub in `VideoPlayerViewController`.

- `ENABLE_DEBUG_SEEK` (Environment Variable; DEBUG builds only)
  - Default: `false`
  - Shows the simple seek slider/time label overlay in the collection feed cell for debugging.

- `UI_TESTING` (Launch Argument)
  - When present, the app loads mock items for stable UI tests and avoids live networking paths.

## How to Set (Xcode)
1. Product → Scheme → Edit Scheme… → Run → Arguments.
2. Environment Variables: add rows (e.g., `API_BASE_URL = https://api.your.com`, `ENABLE_LONG_PRESS_SCRUB = 1`).
3. Arguments Passed On Launch: add `UI_TESTING` if needed.

## How to Set (CLI)
- Prefix `xcodebuild` with `env` to pass environment variables:
  - `env API_BASE_URL=https://api.your.com ENABLE_LONG_PRESS_SCRUB=true xcodebuild -project signal/signal.xcodeproj -scheme signal -configuration Debug build`

## Caching (CDN Alignment)
- `StoryboardProvider` and `ManifestStore` configure `URLCache` (disk ≥ 256 MB) and use `returnCacheDataElseLoad` to honor CDN `Cache-Control`.
- Sprites/VTT and manifests are expected to be versioned URLs; avoid query parameters in cache keys.

## Notes
- Keep `ENABLE_LONG_PRESS_SCRUB` OFF by default until storyboard assets are fully available.
- Startup bitrate cap and lift (~3s) are handled in `PlayerKit`; telemetry is batched via `EventBus`.

## Background Cold‑Start (120s)
- Behavior: if the app stays in background ≥120 seconds, the feed cold‑starts on resume (releases `PlayerPool`, clears items, refetches).
- Location (iOS): `FeedViewModel.didEnterBackground()` and `willEnterForeground()`.
- Testing: the 120s threshold is currently hard‑coded. For UI/QA tests, temporarily adjust the constant in `FeedViewModel` (DEBUG‑only change recommended), or add a short‑lived DEBUG override if needed. Keep release builds at 120s for parity with Android.
