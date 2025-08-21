# Ticket 16 — Data schema extensions: Users.bio/link, Videos.visibility, Bookmarks table
**Date:** 2025-08-16  
**Priority:** P1 (scaffolding)

## TASK
Add minimal data-model support for **Bio**, **Private Videos**, and **Bookmarks** without building full UX.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. This add-on only introduces minimal scaffolding for Bookmark, Share, Bio, and Private Videos. Keep scope tiny, feature-flagged where applicable, and do not change core playback/CDN/manifest rules. Respect EventBus batching and existing DynamoDB keys/GSIs.

## CHANGES
### DynamoDB — Users
- Add attributes: `bio` (string, ≤160 chars), `link_url` (https only), `updated_at`.
- (If present) `Handles` table continues to enforce unique handles.

### DynamoDB — Videos
- Add attribute: `visibility` ∈ `public|private|unlisted` (default: `public`).
- Ensure all items have `owner_id`. Existing **GSI1 (creator timeline)** continues to power author grids.

### DynamoDB — Bookmarks (new table)
- **PK** = `user_id`, **SK** = `video_id`; attrs: `created_at` (ISO8601).
- **GSI1 (optional)** for reverse time: `PK=user_id`, `SK=-created_at` (name: `BookmarksByCreated`).
- Idempotent upsert/delete by `(user_id, video_id)`.

### Redis (counters) — optional
- `user_bookmark_count:{user_id}` (approximate), updated async (do not block main write).

## CONSTRAINTS
- Backfill not required; treat missing fields as defaults (`visibility=public`, `bio=''`).
- All writes **idempotent**. Use conditional expressions where helpful.
- No changes to `media_manifest.json` contract or CDN paths.

## DELIVERABLES
- IaC: `/iac/dynamodb_core_extensions/*` for table updates and new Bookmarks table.
- DAO: `/services/core/dao/users_dao.*`, `/services/core/dao/videos_dao.*`, `/services/core/dao/bookmarks_dao.*`
- Tests: unit tests for conditional writes, idempotent upsert/delete, and URL validation for `link_url`.

## ACCEPTANCE
- Tables/GSIs deployed. DAOs can set `bio/link_url`, toggle `visibility`, and upsert bookmarks idempotently.
- No regressions to existing read paths.
