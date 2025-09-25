# Player Lifecycle Contract (iOS + Android)

Audience: client engineers on both platforms. Purpose: keep attach/ready/play airtight, minimize regressions, and align to industry‑standard TikTok‑style feeds.

## Ownership & Pooling
- A controller (pager/collection) owns a small `PlayerPool` (size 2–3). Cells/fragments never create players.
- Acquire from the pool when a view becomes visible; release back when it goes offscreen. Avoid churn.

## States & Single Play Trigger
- States: `prepared → attached → (playing|paused) → ended(loop) → cleanup`.
- Single play trigger: “attached + item ready + is primary visible cell”. No other path should call `play()` implicitly.
- User pause disables auto‑resume for that item.

## Prepare Semantics
- Input is a resolved `MediaManifest` (manifest is fetched centrally, not by cells).
- Set initial bitrate cap 400–700 kbps; lift after ~3 s of stable playback.
- Begin TTFF measurement at prepare; emit `time_to_first_frame` on first render/ready.

## Attach/Detach
- Only one view/layer attached per player at any time.
- Attach just before becoming visible; detach on recycle/offscreen.
- Observers/time observers must be added/removed symmetrically; remove once and nil tokens. Cancel any tasks tied to old views.

## Visible‑Only Playback Enforcement
- The controller computes the primary visible page (closest to center) and ensures:
  - Primary cell plays.
  - All other visible cells are paused.
- Re‑enforce on scroll end, deceleration end, rotation, and after programmatic jumps.

## Prefetch Policy
- Prewarm current + ~5–8 s next via pool; consider ~3 s previous when resources permit.
- Centralize manifest fetch in a `ManifestStore` that coalesces in‑flight requests and honors CDN cache.

## Telemetry (EventBus)
- Emit (batched ~200 ms):
  - `view_start` on first `play()` per item.
  - `view_end` with `dwell_ms` and `percent_complete` on cleanup/promote/offscreen.
  - `time_to_first_frame` when ready/rendered.
  - `rebuffer` cumulative (`count`, `total_ms`).
  - `selected_bitrate` sampled periodically.
  - `playback_error` on failures.
  - `playback_loop {video_id, loop_count}` on seamless loop.

## App Lifecycle
- If backgrounded ≥120 s: cold start on resume (release pool, refetch feed).
- Otherwise: pause when backgrounding; resume according to previous state.

## Threading & Cancellation
- UI work on main thread; networking/IO off the main thread.
- Cancel binding/fetch tasks when cells recycle or visibility changes.

## Error Handling & UX
- Show tap‑to‑retry overlay on playback failures; keep accessibility labels for video surface and overlays.
- Do not auto‑retry aggressively on poor networks; rely on user tap or next swipe.

## Testing Checklist
- Rapid scroll up/down: only one player audible; no crashes; TTFF within budget.
- Rotation mid‑play: remains single visible; no double‑sound; page snaps correctly.
- Background ≥120 s: pool released; feed refetched on resume.
- Telemetry: one `view_start` per play and exactly one `view_end` per view; TTFF and rebuffer tracked; bitrate samples present.

