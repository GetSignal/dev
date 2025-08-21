# Ticket 19 — Private Videos: visibility enforcement (API + clients)
**Date:** 2025-08-16  
**Priority:** P1 (guardrail)

## TASK
Enforce video `visibility` (public|private|unlisted) across APIs and clients, **without** changing HLS/CDN policy yet.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. This add-on only introduces minimal scaffolding for Bookmark, Share, Bio, and Private Videos. Keep scope tiny, feature-flagged where applicable, and do not change core playback/CDN/manifest rules. Respect EventBus batching and existing DynamoDB keys/GSIs.

## RULES
- `/v1/feed` and FYP must **exclude** `private` items for non-owners.
- Author grid (`GET /users/:user_id/videos`) returns:
  - If `viewer_id == owner_id`: public + private (mark private)
  - Else: public (+ unlisted **only with explicit link**, not listed)
- `media_manifest_url` must **not** be returned to non-owners for `private` items.
- Deep-link resolver (Ticket 18) must respect visibility:
  - `private`: require owner; otherwise show lightweight "unavailable" page in web fallback.
  - `unlisted`: allow access with exact URL but never include in feeds.

## CLIENT UI
- Minimal badge "Private" on owner’s grid items; no additional UX.
- No changes to player behavior beyond gating access (player should not attempt to load private items for non-owners).

## DELIVERABLES
- API: checks in `/v1/feed`, `/users/:user_id/videos`, and the deep-link resolver.
- Clients: filtering in view models to avoid attempting playback for disallowed items; show placeholder tile instead.

## TESTS
- Unit tests: API gating logic (viewer vs owner), resolver behavior for private/unlisted.
- UI tests: grid shows Private badge for owner; non-owners never see private items.

## ACCEPTANCE
- Non-owners cannot receive `media_manifest_url` for private videos.
- Owner sees and can play their private videos from the profile grid.
- Unlisted items accessible only via exact link; never surfaced in feeds.
