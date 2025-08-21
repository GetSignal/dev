# Ticket 13 — APIs: Like/Unlike, Follow/Unfollow, Minimal Profile
**Date:** 2025-08-16  
**Priority:** P1 (scaffolding)

## TASK
Expose minimal REST endpoints for likes/follows and a lightweight profile read.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Add *minimal scaffolding only* for Users/Follows/Likes, keeping scope tiny and safe. Respect CDN/TTL rules, manifest usage, and existing telemetry batching. No on-device frame extraction.

## ENDPOINTS
- `POST /likes?video_id=...` and `DELETE /likes?video_id=...` — **idempotent**; 200/204.
- `POST /follow?user_id=...` and `DELETE /follow?user_id=...` — **idempotent**; 200/204.
- `GET /profiles/:user_id` — returns `user_id`, `handle`, `avatar_url`, (optional) approx counts.
- (Optional) `GET /users/:user_id/videos?cursor=...` — author grid feed.

## CONSTRAINTS
- Auth: Cognito token required; extract `actor_user_id` server-side.
- Rate limits: simple token bucket per actor (e.g., 10 rps burst 20).
- Input validation; clear 4xx on bad params; no PII.
- Counters updated asynchronously (fire-and-forget); do not fail the main write on counter failure.

## DELIVERABLES
- Code: `/services/social/api/*` handlers + validation.
- Tests: unit tests for idempotency, validation, and rate limiting.
- Output: diff-ready code + rationale.

## ACCEPTANCE
- Valid like/follow requests are idempotent; invalid payloads return clear 400.
- Profile returns expected fields; tests pass.
