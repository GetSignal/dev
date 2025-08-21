
# Ticket 5 — Android skeleton & vertical pager (ViewPager2)
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Build a snap-scrolling vertical feed scaffold using ViewPager2.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
Buildable Android shell with snap paging and clean recycling.

## CONSTRAINTS
- Kotlin + ViewPager2 vertical; fast decel; snap behavior.
- Memory stable; pages deallocate when off-screen.
- Espresso test target exists.

## DELIVERABLES
- Files: `/app/android/.../FeedPagerActivity.kt`, `/app/android/.../FeedAdapter.kt`, layouts
- Tests: Espresso test for snap paging and deallocation
- Output: diff-ready code + rationale

## ACCEPTANCE
- Pager shows 3 mock items; snap behavior OK.
- Paging 50 items does not leak.
- Tests pass.
