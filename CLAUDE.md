# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Signal is a TikTok-style short-video platform designed for rapid, smooth playback with a "For You" feed experience. The project targets 1-5M concurrent viewers in the first 6 months with a focus on cost-efficient delivery and native mobile performance.

## Authoritative Specifications

**ALWAYS refer to these documents as the source of truth:**
- `Signal_Agent_Guide.md` - Production build specification with hard guardrails
- `Signal_Agent_Prompt.md` - Implementation approach and requirements

## Architecture

### 7-Stage Pipeline
1. **Capture & Export** - H.264/AAC file from mobile clients
2. **Direct Upload** - Cognito auth → presigned multipart S3 upload
3. **Inspect & Moderate** - Visual-only checks with AWS Rekognition
4. **Transcode & Storyboards** - MediaConvert (CMAF/HLS) + Lambda for sprites
5. **Finalize & Publish** - Create `media_manifest.json`
6. **Delivery & Caching** - CloudFront CDN with specific TTL policies
7. **Playback & Telemetry** - Native players with batched events

### Client Architecture
- **iOS**: Swift/SwiftUI with UIPageViewController
- **Android**: Kotlin with ViewPager2
- **PlayerPool**: Size 2-3, prefetch current + 5-8s of next
- **Scrubbing**: WebVTT storyboards with sprite images (NO on-device frame extraction)
- **Telemetry**: Batched/debounced ~200ms to `/v1/events`

## Build Commands

### iOS Development
```bash
# Build the iOS app
xcodebuild -project signal/signal.xcodeproj -scheme signal -configuration Debug build

# Run tests
xcodebuild test -project signal/signal.xcodeproj -scheme signal -destination 'platform=iOS Simulator,name=iPhone 15'

# Clean build
xcodebuild -project signal/signal.xcodeproj -scheme signal clean

# Archive for release
xcodebuild -project signal/signal.xcodeproj -scheme signal -configuration Release archive
```

### Android Development
```bash
# Build commands will be added when Android project is set up
# ./gradlew build
# ./gradlew test
# ./gradlew assembleDebug
```

## Critical Performance Requirements

**These are non-negotiable budgets that MUST be met:**
- **TTFF (Time to First Frame)**: P75 < 1.2s, P95 < 2.0s (Wi-Fi)
- **CDN Hit Ratio**: ≥97%
- **Rebuffer Ratio**: <1% of playback time
- **Ranker Latency**: P99 ≤30ms or fallback to Trending

## Hard Guardrails (DO NOT CHANGE)

1. **CDN & Cache**: Use versioned immutable paths `/{video_id}/vN/...`, no cookies/headers/query in cache key
2. **Storyboards**: MediaConvert does NOT output sprites - always use Lambda post-step
3. **Client Scrubbing**: Use WebVTT storyboard only, NO on-device frame extraction
4. **Security**: S3 with Origin Access Control, optional signed cookies/URLs for HLS
5. **Auth**: AWS Cognito only (Amplify Auth permitted for speed)
6. **Tech Stack**: Native iOS/Android only - NO React Native, NO cross-fade between items

## Cache TTL Policy
- **Sprites/VTT/Posters**: 1 year immutable (31536000s)
- **Segments**: 7-30 days immutable
- **Manifests**: 15-60s + stale-while-revalidate, stale-if-error=60

## Event Telemetry Format

Events must be batched and sent to `/v1/events`:
```json
{
  "device_id": "ios-abc",
  "session_id": "s-123",
  "ts": 1700000000,
  "events": [
    {"name": "view_start", "props": {"video_id": "a1"}},
    {"name": "view_end", "props": {"video_id": "a1", "dwell_ms": 1543, "percent_complete": 76}},
    {"name": "tap_play_pause", "props": {"playing": true}},
    {"name": "preview_scrub_start"},
    {"name": "preview_scrub_commit", "props": {"seconds": 42}},
    {"name": "time_to_first_frame", "props": {"ms": 740}},
    {"name": "rebuffer", "props": {"count": 1, "total_ms": 340}},
    {"name": "selected_bitrate", "props": {"kbps": 1200}},
    {"name": "playback_error", "props": {"video_id": "a1", "code": "E_HLS_PLAY"}}
  ]
}
```

## Media Manifest Format

Each video has a single `media_manifest.json`:
```json
{
  "video_id": "a1",
  "duration_ms": 183000,
  "hls_url": "https://cdn.example.com/vod/a1/v7/hls/master.m3u8",
  "poster_url": "https://cdn.example.com/vod/a1/v7/poster.jpg",
  "thumbnail_vtt_url": "https://cdn.example.com/vod/a1/v7/storyboard/storyboard.vtt",
  "ladder": [
    {"height": 240, "bitrate": 300000},
    {"height": 360, "bitrate": 600000},
    {"height": 480, "bitrate": 1100000},
    {"height": 720, "bitrate": 2500000}
  ],
  "loudness_lufs": -16.0,
  "created_at": "2025-08-16T12:00:00Z"
}
```

## Implementation Status

### Existing Code
- **iOS**: Full Xcode project with modular architecture (`signal/signal.xcodeproj`)
  - Core components: `EventBus.swift`, `PlayerKit.swift`, `PlayerPool.swift`, `StoryboardProvider.swift`
  - Feed system: `FeedView.swift`, `FeedViewModel.swift`, `VideoPageViewController.swift`
  - Models: `MediaManifest.swift`, `VideoItem.swift`
  - Utilities: `WebVTTParser.swift`
  - Test suites: Unit tests for EventBus and WebVTT parsing
- **Sample Controllers**: `FeedViewController.swift`, `FeedPagerActivity.kt`
- **PlayerKit Samples**: `PlayerKit-iOS.swift`, `PlayerKit-Android.kt`
- **Infrastructure Templates**: `mediaconvert-storyboard-template.json`, `terraform-cloudfront-cache.tf`
- **Utilities**: `sprite-vtt-generator.js`
- **Tickets System**: 23 detailed implementation tickets in `Signal_Tickets_v1/`

### Needs Implementation
- Complete Android app structure
- Backend APIs (`/v1/feed`, `/v1/events`)
- AWS pipeline (Step Functions, Lambda, MediaConvert)
- DynamoDB tables and GSIs
- Performance monitoring dashboards

## Environment Variables

Required configuration (use placeholders in code):
- `API_BASE_URL`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_CLIENT_ID`
- `STORYBOARD_BUCKET`
- `CLOUDFRONT_DISTRIBUTION_ID`

## Key Implementation Rules

1. **Autoplay**: Start with audio ON, use device volume controls
2. **Gestures**: Tap to play/pause, long-press to scrub (resume only if was playing)
3. **Prefetch**: Current + 5-8s of next, initial bitrate cap 400-700 kbps
4. **Caching**: iOS URLCache ≥256MB disk, Android OkHttp ≥50MB
5. **Sprite Cache**: In-memory LRU ~24 images with neighbor prefetch
6. **Error Handling**: Show tap-to-retry overlay, report playback_error event
7. **Lifecycle**: Pause on background/interruption, resume appropriately

## Testing Requirements

- **Unit Tests**: VTT parsing, EventBus batching
- **UI Tests**: Paging gestures, scrub behavior
- **Performance Tests**: TTFF measurement
- **Integration Tests**: Feed API, event delivery

## Development Approach

When implementing features:
1. Follow the Agent Guide guardrails verbatim
2. Use strongly typed, async/await code
3. Keep secrets in environment variables
4. Test against performance budgets
5. Emit all required telemetry events
6. Use conservative defaults for unspecified behavior