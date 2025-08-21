# SwiftUI + ViewPager2 Feed Implementations

This adds production-style feeds on both platforms with vertical paging and recycling.

## iOS (SwiftUI)
- **File:** `SwiftUIFeedView.swift`
- **Approach:** SwiftUI wrapper around `UIPageViewController` with **vertical** navigation.
- **Recycling:** Pages reuse **PlayerPool** instances; previous page's player is returned to the pool after a page flip.
- **Preload:** When a page becomes visible, we **preload the next** item's first seconds from the pool.
- **Telemetry:** Emits `view_end` (dwell + % complete) on page transition via `EventBus`.

**Usage:**
```swift
// Somewhere in your App:
let items = [
  VideoItem(id: "a1", hlsUrl: URL(string:"https://cdn.example.com/vod/a1/master.m3u8")!),
  VideoItem(id: "b2", hlsUrl: URL(string:"https://cdn.example.com/vod/b2/master.m3u8")!)
]
let bus = HttpEventBus(endpoint: URL(string:"https://api.example.com/event")!)
FeedView(items: items, eventBus: bus)
```

## Android (ViewPager2)
- **File:** `FeedPagerActivity.kt`
- **Approach:** `ViewPager2` with `ORIENTATION_VERTICAL`, offscreen limit 1.
- **Recycling:** `RecyclerView.Adapter` acquires players from **PlayerPool** and returns them in `onViewRecycled`.
- **Preload:** On `onPageSelected`, we start current playback and **preload next**.
- **Telemetry:** Emit `view_end` on page change with dwell + % complete.

**Usage:**
```kotlin
startActivity(Intent(this, FeedPagerActivity::class.java))
```
