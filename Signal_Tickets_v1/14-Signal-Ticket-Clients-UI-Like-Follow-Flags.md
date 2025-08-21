# Ticket 14 — Clients: Like & Follow UI (feature-flagged, optimistic)
**Date:** 2025-08-16  
**Priority:** P2 (tiny UI)

## TASK
Add minimal Like and Follow UI on iOS/Android, **behind a remote flag**, with optimistic updates and background confirmation.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Add *minimal scaffolding only* for Users/Follows/Likes, keeping scope tiny and safe. Respect CDN/TTL rules, manifest usage, and existing telemetry batching. No on-device frame extraction.

## UI
- **Like**: double-tap heart + small heart button; update heart state immediately; revert on server failure.
- **Follow**: button on author overlay; immediate UI toggle; revert on failure.
- **Profile (lightweight)**: header with avatar/handle; grid route wired but can show placeholder thumbnails.

## CONSTRAINTS
- Telemetry events: `like_add/remove(video_id)`, `follow_add/remove(user_id)` via existing **EventBus** (batched/debounced).
- Respect offline mode: queue request for retry; surface subtle toasts on failure.
- Keep code paths isolated; full comments/inbox remain out of scope.

## DELIVERABLES
- iOS files: `/app/ios/Feed/LikeButton.swift`, `/app/ios/Feed/FollowButton.swift`, minimal `/app/ios/Profile/ProfileView.swift`.
- Android files: `/app/android/.../ui/LikeButton.kt`, `/app/android/.../ui/FollowButton.kt`, `/app/android/.../ui/ProfileActivity.kt`.
- Tests: unit tests for optimistic state/revert; UI test for double-tap like.
- Output: diff-ready code + rationale.

## ACCEPTANCE
- Feature flag off → no UI.
- Flag on → Like/Follow works with optimistic updates; telemetry captured; tests pass.
