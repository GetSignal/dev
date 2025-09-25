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

---
**Update 2025-09-08: Add Video Caption & Audio fields (central schema)**

### New Fields (Data Model)
- `Videos.caption : string` (UTF-8, soft limit 2,200 chars; store canonical text only).
- `Videos.audio : object` with keys:
  - `title : string?`
  - `artist : string?`
  - `is_original : boolean?` (default `true`; when true and no `title`, clients render “original sound — @author”)

### Indexing & Validation
- No new GSIs required at launch (fields are read via `/v1/feed` by primary key).
- Validate caption length ≤ 2,200; strip control chars; trim whitespace.
- Audio fields optional; omit absent keys rather than storing empty strings.

### Migration/Backfill
- Backfill not required for existing rows (clients gracefully hide overlays when fields are absent).
- Writes idempotent; do not alter `media_manifest.json` structure.

### Contracts Impacted
- **Ticket 07**: `/v1/feed` item extended to include `caption` and `audio` (read path).
- **Ticket 22**: Upload Preflight optionally accepts `caption` and `audio` (write path).
---

---
**Finalized 2025-09-08: Constraints Approved**
- `Videos.caption` max length **2,200 chars** (truncate on write; sanitize control chars).
- `Videos.audio` keys fixed: **title**, **artist**, **is_original** (optional keys; omit if unknown).
- Acceptance: automated schema tests validate max length and key set.
---
