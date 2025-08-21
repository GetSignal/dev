// FeedPagerActivity.kt
// Production-ready feed: ViewPager2 vertical + PlayerPool
// - Audio ON by default (device volume)
// - Tap-to-play/pause
// - Long-press scrub with WebVTT storyboard thumbnails (LRU + neighbor prefetch)
// - Snap scrolling tuned
// - Lifecycle safe (onStart/onStop/onDestroy)
// - Error overlay with tap-to-retry
// - Telemetry flush debounced
// - Accessibility content descriptions
//
// Assumes PlayerKit-Android.kt defines: ExoPlayerKit { prepare(url, ...), play(), pause(), seek(ms), positionMs(), durationMs(), exo(), onEvent }
// Assumes EventBus { enqueue(TelemetryEvent), flushNow() }

package com.signal.playerkit.demo

import android.content.Context
import android.graphics.*
import android.os.*
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import com.google.android.exoplayer2.ui.PlayerView
import com.signal.playerkit.*
import okhttp3.Cache
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

data class VideoItem(val id: String, val hlsUrl: String, val durationMs: Long? = null, val thumbnailHint: String? = null)

// Debouncer
class Debouncer(private val delayMs: Long) {
    private val handler = Handler(Looper.getMainLooper())
    private var r: Runnable? = null
    fun call(run: () -> Unit) {
        r?.let { handler.removeCallbacks(it) }
        val task = Runnable { run() }
        r = task
        handler.postDelayed(task, delayMs)
    }
}

// Thumbnail provider
interface ThumbnailProvider { fun thumbnail(item: VideoItem, seconds: Double, cb: (Bitmap?) -> Unit) }

class LruBitmapCache(private val maxEntries: Int = 24) : LinkedHashMap<String, Bitmap>(16, 0.75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Bitmap>?): Boolean = size > maxEntries
}

// Default provider: WebVTT storyboard + sprite crop (LRU + neighbor prefetch)
class VttStoryboardProvider(context: Context) : ThumbnailProvider {
    data class Cue(val start: Double, val end: Double, val baseUrl: String, val x: Int, val y: Int, val w: Int, val h: Int)
    private val bitmapCache = LruBitmapCache(24)
    private val cuesCache = object : LinkedHashMap<String, List<Cue>>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Cue>>?): Boolean = size > 64
    }
    private val main = Handler(Looper.getMainLooper())
    private val client: OkHttpClient = OkHttpClient.Builder()
        .cache(Cache(File(context.cacheDir, "signal-storyboard-http-cache"), 50L * 1024L * 1024L))
        .build()

    override fun thumbnail(item: VideoItem, seconds: Double, cb: (Bitmap?) -> Unit) {
        val vttUrl = item.thumbnailHint ?: return cb(null)
        ensureCues(vttUrl) { cues ->
            if (cues.isNullOrEmpty()) { cb(null); return@ensureCues }
            val idx = cues.indexOfFirst { seconds >= it.start && seconds < it.end }
            val sel = when {
                idx >= 0 -> idx
                seconds >= cues.last().end -> cues.lastIndex
                else -> 0
            }
            val cue = cues[sel]
            if (sel > 0) prefetchSprite(cues[sel - 1].baseUrl)
            if (sel + 1 < cues.size) prefetchSprite(cues[sel + 1].baseUrl)

            val cached = synchronized(bitmapCache) { bitmapCache[cue.baseUrl] }
            if (cached != null) cb(Bitmap.createBitmap(cached, cue.x, cue.y, cue.w, cue.h))
            else thread {
                try {
                    val req = Request.Builder().url(cue.baseUrl).build()
                    client.newCall(req).execute().use { resp ->
                        val bytes = resp.body?.bytes() ?: return@use main.post { cb(null) }
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        synchronized(bitmapCache) { bitmapCache[cue.baseUrl] = bmp }
                        main.post { cb(Bitmap.createBitmap(bmp, cue.x, cue.y, cue.w, cue.h)) }
                    }
                } catch (_: Exception) { main.post { cb(null) } }
            }
        }
    }

    private fun prefetchSprite(url: String) {
        if (synchronized(bitmapCache) { bitmapCache.containsKey(url) }) return
        thread {
            try {
                val req = Request.Builder().url(url).build()
                client.newCall(req).execute().use { resp ->
                    val bytes = resp.body?.bytes() ?: return@use
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    synchronized(bitmapCache) { bitmapCache[url] = bmp }
                }
            } catch (_: Exception) {}
        }
    }

    private fun ensureCues(vttUrl: String, done: (List<Cue>?) -> Unit) {
        synchronized(cuesCache) { cuesCache[vttUrl]?.let { done(it); return } }
        thread {
            try {
                val req = Request.Builder().url(vttUrl).build()
                client.newCall(req).execute().use { resp ->
                    val text = resp.body?.string()
                    if (text == null) { main.post { done(null) }; return@use }
                    val cues = parseVtt(text)
                    synchronized(cuesCache) { cuesCache[vttUrl] = cues }
                    main.post { done(cues) }
                }
            } catch (_: Exception) { main.post { done(null) } }
        }
    }

    private fun parseVtt(text: String): List<Cue> {
        val out = mutableListOf<Cue>(); var t0: Double? = null; var t1: Double? = null
        text.lineSequence().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("WEBVTT")) return@forEach
            if (line.contains("-->")) {
                val parts = line.split("-->")
                t0 = hmsToSec(parts[0].trim()); t1 = hmsToSec(parts[1].trim())
            } else if (line.contains("#xywh") && t0 != null && t1 != null) {
                val parts = line.split("#xywh=")
                val base = parts[0].trim()
                val nums = parts[1].split(",").map { it.toInt() }
                if (nums.size == 4) out += Cue(t0!!, t1!!, base, nums[0], nums[1], nums[2], nums[3])
                t0 = null; t1 = null
            }
        }
        return out.sortedBy { it.start }
    }

    private fun hmsToSec(t: String): Double {
        val p = t.split(":")
        val secParts = p.last().split(".")
        val s = secParts[0].toDouble()
        val ms = secParts.getOrNull(1)?.let { ("0.$it").toDouble() } ?: 0.0
        return if (p.size == 2) p[0].toDouble() * 60 + s + ms
               else p[0].toDouble() * 3600 + p[1].toDouble() * 60 + s + ms
    }
}

class FeedPagerActivity : AppCompatActivity() {
    private lateinit var pager: ViewPager2
    private var adapter: VideoPagerAdapter? = null
    private val eventBus: EventBus = HttpEventBus("https://api.example.com/event")
    private lateinit var pool: PlayerPool
    private val flushDebouncer = Debouncer(200)

    // Provide items from your feed service
    private var items: List<VideoItem> = listOf(
        // Example with versioned VTT
        // VideoItem("a1", "https://cdn.example.com/vod/a1/master.m3u8", thumbnailHint = "https://cdn.example.com/vod/a1/v7/storyboard.vtt")
    )

    private var currentPos = 0
    private var viewStartTs = 0L
    private var wasPlayingBeforeStop = false
    private lateinit var thumbnailProvider: ThumbnailProvider

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pool = PlayerPool(this, eventBus, 3)
        thumbnailProvider = VttStoryboardProvider(applicationContext)

        if (items.isEmpty()) {
            val tv = TextView(this).apply {
                text = "No videos"
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.BLACK)
                textSize = 16f
                gravity = Gravity.CENTER
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
            setContentView(tv); return
        }

        pager = ViewPager2(this).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            orientation = ViewPager2.ORIENTATION_VERTICAL
            offscreenPageLimit = 1
            (getChildAt(0) as? RecyclerView)?.overScrollMode = View.OVER_SCROLL_NEVER
        }
        setContentView(pager)
        adapter = VideoPagerAdapter(items, pool, eventBus, thumbnailProvider, flushDebouncer)
        pager.adapter = adapter

        pager.registerOnPageChangeCallback(object: ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                super.onPageSelected(position)
                adapter?.getBoundAt(currentPos)?.let { holder ->
                    emitViewEnd(items[currentPos], holder.boundPlayer)
                    holder.boundPlayer?.pause()
                }
                currentPos = position
                adapter?.getBoundAt(position)?.boundPlayer?.play()
                viewStartTs = System.currentTimeMillis()
                // Preload next and previous
                val next = position + 1
                if (next < items.size) pool.preloadNext(items[next].hlsUrl)
                val prev = position - 1
                if (prev >= 0) pool.preloadNext(items[prev].hlsUrl)
            }
        })

        pager.post {
            adapter?.getBoundAt(0)?.boundPlayer?.play()
            viewStartTs = System.currentTimeMillis()
            if (items.size > 1) pool.preloadNext(items[1].hlsUrl)
        }
    }

    override fun onStart() {
        super.onStart()
        if (wasPlayingBeforeStop) {
            adapter?.getBoundAt(currentPos)?.boundPlayer?.play()
            wasPlayingBeforeStop = false
        }
    }

    override fun onStop() {
        super.onStop()
        val player = adapter?.getBoundAt(currentPos)?.boundPlayer
        wasPlayingBeforeStop = player?.exo()?.isPlaying == true
        player?.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Ensure release of currently bound player
        adapter?.getBoundAt(currentPos)?.boundPlayer?.let { pool.release(it) }
    }

    private fun emitViewEnd(item: VideoItem, pk: ExoPlayerKit?) {
        if (pk == null) return
        val dwell = System.currentTimeMillis() - viewStartTs
        val pos = pk.positionMs().toDouble()
        val dur = if (pk.durationMs() > 0) pk.durationMs().toDouble() else 1.0
        val pct = ((pos / dur) * 100.0).toInt()
        eventBus.enqueue(TelemetryEvent("view_end", mapOf("video_id" to item.id, "dwell_ms" to dwell, "percent_complete" to pct)))
        flushDebouncer.call { eventBus.flushNow() }
    }
}

// Adapter + ViewHolder

class VideoPagerAdapter(
    private val items: List<VideoItem>,
    private val pool: PlayerPool,
    private val eventBus: EventBus,
    private val thumbnailProvider: ThumbnailProvider,
    private val flushDebouncer: Debouncer
): RecyclerView.Adapter<VideoViewHolder>() {
    private val bound = mutableMapOf<Int, VideoViewHolder>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VideoViewHolder {
        val root = FrameLayout(parent.context).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundColor(Color.BLACK)
        }
        val pv = PlayerView(parent.context).apply {
            layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            useController = false
            contentDescription = "Video player"
        }
        val overlay = ScrubOverlayView(parent.context)
        val error = ErrorOverlayView(parent.context)
        root.addView(pv); root.addView(overlay); root.addView(error)
        return VideoViewHolder(root, pv, overlay, error, thumbnailProvider, eventBus, flushDebouncer, pool)
    }

    override fun onBindViewHolder(holder: VideoViewHolder, position: Int) {
        val item = items[position]
        val pk = pool.acquire()
        holder.bind(item, pk)
        bound[position] = holder
    }

    override fun onViewRecycled(holder: VideoViewHolder) {
        super.onViewRecycled(holder)
        holder.unbind()
        bound.entries.removeAll { it.value == holder }
    }

    override fun getItemCount(): Int = items.size
    fun getBoundAt(position: Int): VideoViewHolder? = bound[position]
}

class ScrubOverlayView(context: Context): FrameLayout(context) {
    val image = ImageView(context); val label = TextView(context)
    init {
        setPadding(16, 16, 16, 16); setBackgroundColor(0x88000000.toInt())
        visibility = View.GONE
        isFocusable = false; isClickable = false
        contentDescription = "Scrub Preview"
        val wrap = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; topMargin = 80
        }
        image.layoutParams = wrap
        label.setTextColor(Color.WHITE); label.textSize = 12f
        val inner = FrameLayout(context); inner.addView(image)
        inner.addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; bottomMargin = 8
        })
        addView(inner)
    }
}

class ErrorOverlayView(context: Context): FrameLayout(context) {
    val label = TextView(context)
    var onRetry: (() -> Unit)? = null
    init {
        setPadding(24, 16, 24, 16); setBackgroundColor(0x88000000.toInt())
        visibility = View.GONE
        contentDescription = "Playback error. Tap to retry."
        label.text = "Playback error. Tap to retry"
        label.setTextColor(Color.WHITE); label.textSize = 14f
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
        })
        setOnClickListener { onRetry?.invoke() }
    }
}

class VideoViewHolder(
    root: View,
    private val playerView: PlayerView,
    private val overlay: ScrubOverlayView,
    private val errorOverlay: ErrorOverlayView,
    private val thumbProvider: ThumbnailProvider,
    private val eventBus: EventBus,
    private val flushDebouncer: Debouncer,
    private val pool: PlayerPool
): RecyclerView.ViewHolder(root) {
    var boundPlayer: ExoPlayerKit? = null
        private set
    private var item: VideoItem? = null
    private var isPlaying = false
    private var wasPlayingBeforeScrub = false
    private val handler = Handler(Looper.getMainLooper())
    private var lastThumbMs = 0L

    fun bind(item: VideoItem, pk: ExoPlayerKit) {
        this.item = item
        boundPlayer = pk
        playerView.player = pk.exo()
        playerView.contentDescription = "Video ${item.id}"

        // Tap-to-play/pause
        playerView.setOnClickListener {
            val p = boundPlayer?.exo() ?: return@setOnClickListener
            if (p.isPlaying) { pause() } else { play() }
            eventBus.enqueue(TelemetryEvent("tap_play_pause", mapOf("playing" to isPlaying)))
            flushDebouncer.call { eventBus.flushNow() }
        }

        // Long-press to scrub
        val gesture = object: GestureDetector.SimpleOnGestureListener() {
            override fun onLongPress(e: MotionEvent) {
                wasPlayingBeforeScrub = isPlaying
                pause()
                overlay.visibility = View.VISIBLE
                eventBus.enqueue(TelemetryEvent("preview_scrub_start"))
                updateScrub(e.x)
                flushDebouncer.call { eventBus.flushNow() }
            }
            override fun onScroll(e1: MotionEvent, e2: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
                if (overlay.visibility == View.VISIBLE) {
                    updateScrub(e2.x)
                    return true
                }
                return false
            }
        }
        val detector = GestureDetector(playerView.context, gesture)
        playerView.setOnTouchListener { _, ev ->
            detector.onTouchEvent(ev)
            if (ev.action == MotionEvent.ACTION_UP || ev.action == MotionEvent.ACTION_CANCEL) {
                if (overlay.visibility == View.VISIBLE) {
                    overlay.visibility = View.GONE
                    val dur = (boundPlayer?.durationMs() ?: 0L).coerceAtLeast(100L)
                    val width = playerView.width.coerceAtLeast(1)
                    val fraction = (ev.x / width).coerceIn(0f, 1f)
                    val targetMs = (fraction * dur).toLong()
                    boundPlayer?.seek(targetMs)
                    if (wasPlayingBeforeScrub) play()
                    eventBus.enqueue(TelemetryEvent("preview_scrub_commit", mapOf("ms" to targetMs)))
                    flushDebouncer.call { eventBus.flushNow() }
                }
            }
            false
        }

        errorOverlay.onRetry = {
            errorOverlay.visibility = View.GONE
            boundPlayer?.prepare(item.hlsUrl, initialBitrateCapKbps = 700)
            play()
        }

        pk.onEvent = { name, _ ->
            when (name) {
                "playback_start" -> { isPlaying = true; errorOverlay.visibility = View.GONE }
                "paused", "ended" -> isPlaying = false
                "error", "playback_error" -> {
                    isPlaying = false
                    errorOverlay.visibility = View.VISIBLE
                    eventBus.enqueue(TelemetryEvent("playback_error", mapOf("video_id" to item.id)))
                    flushDebouncer.call { eventBus.flushNow() }
                }
            }
        }
        pk.prepare(item.hlsUrl, initialBitrateCapKbps = 700) // Activity starts playback
    }

    fun unbind() {
        pause()
        boundPlayer?.dispose()
        boundPlayer?.let { pool.release(it) }
        boundPlayer = null
        item = null
    }

    private fun play() { boundPlayer?.play(); isPlaying = true }
    private fun pause() { boundPlayer?.pause(); isPlaying = false }

    private fun updateScrub(x: Float) {
        val it = item ?: return
        val dur = (boundPlayer?.durationMs() ?: 0L).coerceAtLeast(100L)
        val width = playerView.width.coerceAtLeast(1)
        val fraction = (x / width).coerceIn(0f, 1f)
        val targetSec = (fraction * dur).toLong() / 1000.0
        overlay.label.text = toTime(targetSec)
        overlay.x = (playerView.width - overlay.width) / 2f
        overlay.visibility = View.VISIBLE

        val now = SystemClock.uptimeMillis()
        if (now - lastThumbMs < 120) return
        lastThumbMs = now

        thumbProvider.thumbnail(it, targetSec) { bmp -> handler.post { overlay.image.setImageBitmap(bmp) } }
    }

    private fun toTime(seconds: Double): String {
        val total = seconds.toInt()
        val m = total / 60; val s = total % 60
        return String.format("%02d:%02d", m, s)
    }
}
