# Ticket 18 — Share: deep links, resolver, and telemetry
**Date:** 2025-08-16  
**Priority:** P2 (routing + telemetry)

## TASK
Reserve canonical share links and implement a minimal resolver + client share-sheet wiring.

## CONTEXT
Use **“Signal — Agent Guide (Production Build Spec)”** as the authoritative spec. This add-on only introduces minimal scaffolding for Bookmark, Share, Bio, and Private Videos. Keep scope tiny, feature-flagged where applicable, and do not change core playback/CDN/manifest rules. Respect EventBus batching and existing DynamoDB keys/GSIs.

## DELIVERABLES
### Link pattern
- Canonical: `https://signal.example.com/v/{video_id}`

### Server
- `GET /v/{video_id}` resolver: if app installed, open deep link; else simple HTML with Open Graph tags (title, poster) and store links.
- Publish **Apple App Site Association** and **Android assetlinks.json** for Universal/App Links.

### Clients
- iOS: Use OS share sheet with the canonical URL; handle Universal Link to open directly in app to the video.
- Android: Use ShareCompat/Intent; handle App Link to open to the video.
- EventBus: `share(video_id, channel)` where `channel ∈ {copy, messages, sms, email, other}`.

## CONSTRAINTS
- No attribution service yet; no URL shortener required for MVP.
- Respect privacy: do not include user identifiers in the link.
- Deep link open should **not** bypass visibility rules (see Ticket 19).

## TESTS
- Smoke tests: links open app on supported OS; fallback HTML renders poster and title.
- Unit tests: telemetry payload for share events.

## ACCEPTANCE
- Share sheet produces canonical URL that resolves to the correct video.
- Universal/App Links verified in dev/test.
- Share telemetry emitted and batched.
