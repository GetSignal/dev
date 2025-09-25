Here’s a practical, best‑practice implementation plan for a seek bar that fits a TikTok‑style app and preserves smooth paging,
  autoplay, and looping.
  
  Behavior & UX (both platforms)
  
  - Visibility: Hidden while playing; visible only when paused or during explicit interaction (tap to pause reveals; long‑press
  scrub remains off by default).
  - Interaction:
      - Dragging updates the current time label and (if available) storyboard thumbnail preview.
      - On release, seek to the target time and resume only if the video was playing before the interaction.
  - Non‑interference: The seek bar must not block vertical paging; gestures must be non‑greedy and allow page pan to win on vertical
  drag.
  - Accessibility: Proper labels for the slider (“Video position”), current time/duration announcements, and large touch targets.
  
  iOS implementation plan
  
  - Overlay
      - Add a lightweight seek overlay view (UIStackView with UISlider + time label) anchored above safe area.
      - Show when paused or when user taps a small “progress” affordance; hide when playing.
  - Slider behavior
      - TouchDown: record wasPlayingBeforeSeek = isPlaying; pause(); show preview overlay; throttle updates (~8–12 FPS).
      - ValueChanged: compute target seconds; update time label and request storyboard thumbnail (if available); do not call play()
  yet.
      - TouchUp: player.seek(to target); if wasPlayingBeforeSeek, play(); hide preview; hide slider if you want it “paused‑only”.
  - Player integration
      - Use existing PlayerKit; add a “preview seek” API only if needed (seek without auto‑resume is already supported via the
  current pause/seek/play flow).
  - Telemetry
      - Emit preview_scrub_start on TouchDown; preview_scrub_commit on release with seconds; keep loop telemetry and view_end
  unchanged.
  - Gesture priority
      - Slider’s pan must not cancel vertical paging: set cancelsTouchesInView=false and require page pan to win for vertical
  movement (already wired).
  
  Android implementation plan
  
  - Overlay
      - Add a SeekBar + time label overlay (FrameLayout anchored to bottom) inside the ViewHolder’s root view.
      - Visibility rules same as iOS (visible on pause or explicit interaction).
  - SeekBar behavior
      - OnStartTrackingTouch: wasPlayingBeforeSeek = isPlaying; pause(); show overlay; throttle preview requests (~8–12 FPS).
      - OnProgressChanged(fromUser):
      - Compute targetMs; update label; request storyboard thumbnail if available.
  - OnStopTrackingTouch: exo.seekTo(targetMs); if wasPlayingBeforeSeek, play(); hide preview; hide seek bar if you prefer
  paused‑only.
  - Player integration
      - Reuse ExoPlayerKit; no new API needed. Ensure the loop logic remains intact (on STATE_ENDED).
  - Telemetry
      - Emit preview_scrub_start and preview_scrub_commit, plus existing playback_loop and others.
  
  Storyboards & performance (both)
  
  - Thumbnails: Only show preview images when thumbnail_vtt_url with #xywh is available; otherwise show time only.
  - Caching & throttle: Maintain existing LRU caches and throttle preview loads to ~8–12 FPS to avoid jank.
  - Memory: Release previews on cell reuse/detach (Android/iOS) and cancel in‑flight fetches.
  
  Single‑playback enforcement (both)
  
  - After any seek commit, re‑enforce only one visible player is playing (collection view: on scroll end and rotation completion;
  iOS already implemented; mirror on Android after seek events).
  - Looping stays active: Seek does not break looping; on end, resume loop from 0.
  
  Background & rotation (both)
  
  - Respect the 120s background cold‑start policy.
  - On rotation, snap and re‑enforce a single playing cell before hiding overlays; seek bar state resets to match the current
  position.
  
  Rollout & flags
  
  - Feature flag the seek bar (“SHOW_SEEKBAR”) for staged rollout.
  - Keep long‑press scrub OFF by default; the seek bar covers QA needs without conflicting with paging.
  
  QA checklist
  
  - Autoplay + seek bar: every item auto‑plays on entry; tapping to pause shows seek bar; dragging seeks accurately; resume only if
  it was playing before.
  - Paging: vertical snap remains smooth; seek bar/preview doesn’t block scroll.
  - Loop: end reaches loop; seek still loops seamlessly.
  - Rotation: portrait/landscape transitions keep one active player; seek bar state updates correctly.
  - Background: cold‑start path after 120s behaves as expected.
  
  If you want, I can start with Android’s SeekBar overlay in the existing ViewHolder (low risk), then add the iOS UISlider overlay
  after that, matching telemetry and behavior exactly.

=================

  > Overview
  
  - Visibility: Hidden while playing; shows when paused or during interaction; auto-hides 1.5–2.0 s after resume.
  - Placement: Bottom overlay above safe area/home indicator; full‑width with 16 pt/dp horizontal inset; sits atop a subtle
  bottom scrim.
  - Components: Slider (track + thumb), current time label, duration label, optional preview thumbnail bubble above the
  thumb.
  
  Common Specs
  
  - Scrim: 72–96 pt/dp tall gradient (transparent→#000 60%) to separate controls from video.
  - Track: Height 4 pt/dp; active color = brand (iOS: systemBlue; Android: #2196F3), inactive = white 30%, buffered
  (optional MVP) = white 50%.
  - Thumb: Size 24 pt/dp; touch target minimum 44 pt (iOS) / 48 dp (Android).
  - Labels: Current (left) and duration (right), white 90%, 12–14 pt/dp; monospace or tabular figures preferred.
  - Preview Bubble: 120×68 pt/dp (16:9) with 8 pt radius, drop shadow; only shown when WebVTT sprites (#xywh) exist; sits
  56–72 pt/dp above thumb.
  - Interaction: Drag updates label/preview at ~8–12 FPS; on release, seek; resume only if it was playing before; cancel
  returns to prior state.
  - Gesture Safety: Non‑greedy; vertical drags still page. Horizontal drag threshold 8–12 pt/dp before intercept.
  - Accessibility: Slider label “Video position”; value announces “mm:ss of mm:ss”; actions labeled (“Preview scrub start/
  commit”, “Retry” remains in error overlay); contrast ≥ 4.5:1.
  - Auto‑Hide: When playing, fade out overlay in 250 ms after 1.5–2.0 s inactivity.
  
  iOS
  
  - Layout: UIStackView pinned to bottom safe area; [current] [slider] [duration], 16 pt padding; preview bubble centered
  above slider thumb.
  - Gesture Priority: cancelsTouchesInView=false; require slider/tap to fail against pageViewController.gestureRecognizers
  for vertical pans.
  - Slider Steps: 1 s increments; continuous updates throttled to ~100–125 ms.
  - Haptics: Light impact on seek commit and when snapping to start/end (optional).
  - Colors: Use system colors (e.g., tintColor = .systemBlue); labels UIColor.white.withAlphaComponent(0.9).
  
  Android
  
  - Layout: FrameLayout bottom overlay inside ViewHolder; SeekBar + two TextViews; preview bubble as ImageView + label
  above thumb.
  - Pager Interop: Ensure SeekBar only intercepts horizontal motion; keep ViewPager2 vertical pan unaffected; child
  RecyclerView overScrollMode=NEVER.
  - Ripple/States: Standard Material ripple on thumb (optional); SeekBar max = duration seconds; progress by seconds.
  - Colors: Active = #2196F3; inactive = white 30%; labels white/gray as above.
  
  Performance
  
  - Throttle: Preview fetch limited to 8–12 FPS; ignore redundant requests within 100–125 ms.
  - Caching: iOS URLCache ≥ 256 MB; Android OkHttp cache ≥ 50 MB; LRU bitmap cache ≈24 sprites; neighbor prefetch (±1 cue).
  - Memory: Release preview bitmaps on cell reuse/detach; cancel in‑flight requests on interaction end.
  
  Telemetry
  
  - Events: preview_scrub_start, preview_scrub_commit {seconds}, existing tap_play_pause, playback_loop, view_end.
  - Batching: Via existing EventBus (~200 ms debounce), with device/session ids.
  
  States & Edge Cases
  
  - No VTT: Hide preview image; show time labels only.
  - Looping: Seek must not disable looping; on end, loop from 0.
  - Background/Rotation: Respect 120 s cold‑start policy; on rotation, keep single active player and rebind overlay to
  current position.
  
  Controls & Flags
  
  - Feature Flag: SHOW_SEEKBAR (default OFF until paging gesture require‑to‑fail finalized); long‑press scrub stays OFF
  by default.
  - User Flow: Tap video → pause → reveal seek bar; drag → preview; release → seek; resume only if playing before;
  auto‑hide after resume.