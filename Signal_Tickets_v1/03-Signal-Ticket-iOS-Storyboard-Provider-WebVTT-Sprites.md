
# Ticket 3 — iOS storyboard provider (WebVTT sprites) + long-press scrub
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Implement a WebVTT storyboard thumbnail provider and wire long-press scrub.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Preview frames during long-press; resume playback only if previously playing.

## CONSTRAINTS
- Parse WebVTT with `#xywh`; crop from sprite JPGs.
- **LRU cache** (~24 sprites) + neighbor prefetch; throttle ~8 FPS.
- Respect Cache-Control via URLCache.
- No on-device frame extraction.

## DELIVERABLES
- Files: `/app/ios/Player/StoryboardThumbnailProvider.swift`, wire gesture in `/app/ios/Player/VideoContentViewController.swift`
- Tests: VTT parsing edge cases; LRU eviction
- Output: diff-ready code + rationale

## ACCEPTANCE
- Long-press pauses and shows thumbnails.
- Release seeks and resumes only if previously playing.
- Throttle and neighbor prefetch active.
- Tests pass.
