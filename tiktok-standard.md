> Here’s the best, targeted way forward that’s standard for TikTok‑style feeds, with zero hacks.

  Immediate (stabilize now)

  - Revert feed controller to last known‑good: per‑cell player ownership (no pooling), manifest fetched via ManifestStore, single play trigger when attached+ready+visible.
  - Deterministic first frame: enforce “attach layer → prepare → if primary visible then play” on first cell; no timing reliance.
  - Cancel on reuse: cancel any pending work in prepareForReuse/didEndDisplaying; never attach after a cell is recycled.
  - Verify with a single known‑good URL (the one you provided), then expand to a small 5–10 URL set.

  Reintroduce pooling correctly (flagged rollout)

  - Identity binding: every async bind carries itemID + generation token; on completion, attach only if cell.itemID and token still match.
  - Aggressive cancellation: cancel binding tasks on reuse/endDisplay; don’t release a player to the pool until all binds for that cell are cancelled.
  - Single play trigger + visible‑only: play only when attached+ready+primary visible; pause all others on scroll/rotation; re‑enforce on viewDidAppear and scroll end.
  - Layer/layout safety: attach AVPlayerLayer before play; update its frame in layoutSubviews; detach on reuse.
  - Prefetch discipline: pool size 2–3; prewarm current + 5–8 s next (and ~3 s previous when allowed) using ManifestStore; keep startup bitrate cap with ~3 s lift.

  Validation (must pass before enabling pooling)

  - Scenarios: first cell auto‑plays; rapid scroll up/down; rotate mid‑play; background ≥120 s then resume; slow network; error streams.
  - Signals: zero black cells, no audio/video mismatch, single visible player at all times; TTFF does not regress.
  - Flag rollout: enable pooling in staging first; then a small internal cohort; promote only after soak.

  Backend hygiene (avoid empty feed surprises)

  - Keep FALLBACK_DAYS at 5–7 and trending writer healthy so /v1/feed never under‑fills.
  - Test manifests via curl/Safari on the target device/network before adding to the set.

  If you want, I can execute Phase 1 (revert to stable per‑cell, cancel-on-reuse, deterministic first play) and stop there for your verification, then submit a separate, small
  PR that adds the identity/cancellation mechanics behind a flag for pooling.