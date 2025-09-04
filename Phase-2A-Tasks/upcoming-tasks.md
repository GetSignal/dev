Upcoming Roadmap Items After Phase 1

## Phase 2A: Complete Core Platform Foundation

1. Implement `/v1/events` API service (Priority P1)
EventBus telemetry from iOS client needs a backend service to accept batched events.
Based on: Signal_Tickets_v1/08-Signal-Ticket-Events-API-Stub-Ingest.md
Suggested task
Create REST endpoint with schema validation and rate limiting

2. Implement `/v1/feed` API client integration (Priority P1)  
iOS client currently uses mock data; needs real backend video content delivery.
Based on: Signal_Tickets_v1/07-Signal-Ticket-Clients-Feed-API-Manifest-Consumption.md
Suggested task
Connect clients to `/v1/feed` API and consume `media_manifest.json`

3. Build Android vertical pager (Priority P1)
Platform parity requires Android equivalent of iOS UIPageViewController implementation.
Based on: Signal_Tickets_v1/05-Signal-Ticket-Android-Vertical-Pager.md  
Suggested task
Implement ViewPager2 with snap behavior and Espresso tests

4. Implement Android PlayerKit & storyboard provider (Priority P1)
Complete Android video experience needs ExoPlayer integration with WebVTT scrubbing.
Based on: Signal_Tickets_v1/06-Signal-Ticket-Android-PlayerKit-Storyboard-Provider.md
Suggested task
Build Android equivalent of iOS PlayerKit functionality

5. Deploy AWS media pipeline infrastructure
Backend lacks the 7-stage media processing pipeline defined in Agent Guide.
Based on: Signal_Tickets_v1/09-11 (MediaConvert, CDN, CloudFront)
Suggested task
Implement transcoding, storyboard generation, and CDN delivery

## Phase 2B: Social Platform Foundation

6. Establish social data storage for users, follows, and likes
Backend lacks tables/GSIs to persist basic social relationships, hindering profile and engagement features.
Suggested task
Add DynamoDB scaffolding for Users/Follows/Likes

7. Expose like/follow/profile endpoints
No REST handlers exist for creating likes/follows or fetching minimal profiles.
Suggested task
Implement social REST APIs

8. Client-side Like/Follow UI behind feature flag
Feed controllers show no interaction widgets; optimistic updates are required.
Suggested task
Add Like/Follow UI components

9. Integrate social features into ranking
Ranker currently ignores follows/likes, limiting personalization.
Suggested task
Feed social signals into ranker features

## Phase 3: Enhanced Social Features

10. Extend data schema for bios, visibility, and bookmarks
User and video tables lack fields for bio/link and visibility; no bookmark table exists.
Suggested task
Add bio, visibility, and bookmarks schema

11. Bookmark APIs and flagged UI
No server/client support for bookmarking videos.
Suggested task
Implement bookmark endpoints and UI

12. Canonical share links and deep-link resolver
Sharing currently lacks URL generation and telemetry.
Suggested task
Add share link resolver and client hooks

13. Enforce private/unlisted video visibility
APIs and clients must respect a visibility flag to restrict access.
Suggested task
Implement visibility checks for videos

## Phase 4: Creator Tools & Upload Workflows

14. Upload session initiation and preflight service
Backend lacks an API to issue presigned part URLs or accept probe metadata.
Suggested task
Provide Upload Session API

15. Multi-select resumable bulk uploader
Current codebase lacks uploading functionality for creators.
Suggested task
Build mobile S3 multipart bulk uploader

16. Cloud/Drive file pickers feeding the uploader
Users cannot select assets from Files/Drive providers.
Suggested task
Integrate cloud file pickers

17. Ingest status dashboard for creators
Creators need visibility into pipeline progress after uploading.
Suggested task
Implement upload status dashboard


These steps extend Signal beyond its Phase 1 baseline — adding platform foundation, social interactions, enhanced features, and creator tools — while adhering to the existing architecture and telemetry conventions.

The roadmap follows a strict dependency chain with four distinct phases:

**Phase 2A** establishes core platform infrastructure (items 1-5) — the events API, feed integration, Android parity, and AWS pipeline. These are foundational requirements that must complete before social features can function properly.

**Phase 2B** builds the social platform foundation (items 6-9) — data storage, REST APIs, UI components, and ranking integration. Items within this phase have dependencies: data schema → APIs → UI → ranking.

**Phase 3** enhances social functionality (items 10-13) — extending schemas, bookmarks, sharing, and visibility controls. These features depend on Phase 2B's social foundation being stable.

**Phase 4** enables creator workflows (items 14-17) — upload initiation, bulk uploading, file pickers, and status dashboards. These can develop independently but follow internal dependencies: session API → uploader → file pickers → dashboard.

This phased approach ensures each layer is solid before building the next, with minimal cross-phase dependencies and clear completion criteria.