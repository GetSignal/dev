
# Ticket 1 — Implement iOS vertical pager (SwiftUI + UIPageViewController)
**Date:** 2025-08-16  
**Priority:** P1

## TASK
Build a snap-scrolling vertical feed scaffold using SwiftUI with a UIKit vertical pager. Include empty/error states.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Follow all guardrails (CDN/TTL, versioned paths, PlayerPool size, initial bitrate cap, WebVTT storyboard pipeline, DynamoDB keys/GSIs). No on-device frame extraction; clients must read `media_manifest.json`.


## GOAL
A buildable iOS app shell that renders a 3-item mock vertical feed with snap paging and clean recycling.

## CONSTRAINTS
- SwiftUI app shell; wrap **UIPageViewController** via `UIViewControllerRepresentable` for vertical paging.
- Memory stable; ensure off-screen pages deallocate.
- No RN/FlashList/Redux.
- UI and unit test targets exist.

## DELIVERABLES
- Files: `/app/ios/App/SignalApp.swift`, `/app/ios/Feed/VideoPagerController.swift`, `/app/ios/Feed/FeedView.swift`
- Tests: UI test verifying vertical snap paging and deallocation
- Output: diff-ready code + short rationale

## ACCEPTANCE
- App launches to pager with 3 mock items.
- Paging is snap-like (no bounce, fast decel).
- Paging 50 items does not leak memory.
- Tests pass locally.
