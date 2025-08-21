# Ticket 17 — Bookmarks: APIs + feature-flagged UI
**Date:** 2025-08-16  
**Priority:** P2 (tiny UI + APIs)

## TASK
Expose **idempotent** endpoints for bookmarking and wire a **flagged** client UI with optimistic updates.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. This add-on only introduces minimal scaffolding for Bookmark, Share, Bio, and Private Videos. Keep scope tiny, feature-flagged where applicable, and do not change core playback/CDN/manifest rules. Respect EventBus batching and existing DynamoDB keys/GSIs.

## ENDPOINTS
- `POST /bookmarks?video_id=...` → 200 (idempotent add)
- `DELETE /bookmarks?video_id=...` → 204 (idempotent remove)
- (Optional) `GET /bookmarks?cursor=...` → returns current user's bookmarks (paged, newest first)

## CONSTRAINTS
- Auth: require Cognito; derive `actor_user_id` server-side.
- Rate limiting (token bucket) to protect write paths.
- EventBus events: `bookmark_add(video_id)`, `bookmark_remove(video_id)` (batched/debounced as per guide).
- Client UI **behind remote flag**; perform optimistic toggle, revert on failure; display subtle toast on error.

## CLIENT DELIVERABLES
- iOS: `/app/ios/Feed/BookmarkButton.swift` (icon only), view model call, optimistic state, flag gating.
- Android: `/app/android/.../ui/BookmarkButton.kt`, view model call, optimistic state, flag gating.

## SERVER DELIVERABLES
- Handlers: `/services/bookmarks/api/*` using Bookmarks DAO.
- Validation: ensure `video_id` format; return clear 4xx for bad input.

## TESTS
- Unit tests: idempotent add/remove, rate-limit behavior, optimistic state revert.
- UI test: double interaction path (tap bookmark; toggle visible state persists across pager recycle).

## ACCEPTANCE
- With flag ON: bookmark icon toggles instantly; server confirms in background; telemetry captured.
- With flag OFF: UI hidden; server endpoints still functional.
