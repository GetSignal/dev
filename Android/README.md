# Signal Android — Build Flags and Debug Caching

## Build Flags (BuildConfig)
- `API_BASE_URL` (String)
  - Default: `https://api.example.com`
  - Used by `FeedService` to fetch `/v1/feed` and item manifests.
- `ENABLE_LONG_PRESS_SCRUB` (boolean)
  - Default: `false`
  - Feature flag for long‑press storyboard scrub overlay.

## How to Override (rebuild required)
- Environment variables:
  - `API_BASE_URL=https://api.your.com ENABLE_LONG_PRESS_SCRUB=true ./gradlew assembleDebug`
- Gradle properties (CLI):
  - `./gradlew assembleDebug -PAPI_BASE_URL=https://api.your.com -PENABLE_LONG_PRESS_SCRUB=true`
- gradle.properties (project root or `~/.gradle/gradle.properties`):
  - `API_BASE_URL=https://api.your.com`
  - `ENABLE_LONG_PRESS_SCRUB=true`

## Debug HTTP Cache Logging
- In debug builds, the client logs whether responses are served from `CACHE` or `NETWORK` (tag `HTTP`).
- Location: `FeedService` OkHttp client interceptor (DEBUG‑only).
- Use logcat filter:
- `adb logcat -s HTTP`

Notes:
- Keep the flag `ENABLE_LONG_PRESS_SCRUB` OFF in release by default until storyboard assets are fully available.
- OkHttp cache is enabled (32 MB for feed/manifest); storyboard provider separately uses a 50 MB cache.

## Background Cold‑Start (120s)
- Behavior: if the app stays in background ≥120 seconds, the feed cold‑starts on resume (releases players and refetches).
- Location (Android): `FeedPagerActivity.onStop()`/`onStart()` with a `120_000` ms threshold.
- Testing: the threshold is currently hard‑coded. For QA, temporarily adjust the constant in `FeedPagerActivity` (DEBUG‑only change recommended) or introduce a temporary BuildConfig override for debug builds. Keep release builds at 120s for parity with iOS.
