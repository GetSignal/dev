# Ticket 12 — Data layer: Users, Follows, Likes (DynamoDB + Redis)
**Date:** 2025-08-16  
**Priority:** P1 (scaffolding)

## TASK
Create minimal tables and indexes to support profiles, follow edges, and likes counters without building full UX yet.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. Add *minimal scaffolding only* for Users/Follows/Likes, keeping scope tiny and safe. Respect CDN/TTL rules, manifest usage, and existing telemetry batching. No on-device frame extraction.

## GOAL
Stable keys/GSIs to avoid refactors later; cheap counters via Redis; idempotent writes.

## SCHEMA (DynamoDB)
- **Users**: `PK=user_id`, attrs: `handle` (unique), `avatar_url`, `created_at`.
- **Follows**: `PK=follower_id`, `SK=followee_id`; **GSI1**: `followee_id` → `follower_id` (fans lookup).
- **Likes**: `PK=video_id`, `SK=user_id`; **GSI1**: `user_id` → `video_id` (user likes).

## CONSTRAINTS
- Conditional writes to enforce uniqueness where applicable (handle uniqueness can be deferred or stored in a small `Handles` table: `PK=handle`, `value=user_id`).
- Soft-delete via tombstones (status=deleted) to allow idempotency.
- **Redis counters**: `video_like_count:{video_id}`, `author_followers:{user_id}` with async backfill; do **not** block user actions on counter writes.

## DELIVERABLES
- IaC: `/iac/dynamodb_social/*` (Terraform or CDK) for tables + GSIs (+ optional `Handles` table).
- Code stub: `/services/social/dao/*` for put/get and conditional write helpers.
- Tests: unit tests for conditional writes and idempotent upserts.
- Output: diff-ready code blocks + rationale.

## ACCEPTANCE
- Tables/GSIs create successfully; DAO can upsert/delete follow/like edges idempotently.
- Redis counters increment/decrement with safe fallback; unit tests pass.
