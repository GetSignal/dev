// FeedFragment.kt
// Signal Video — Feed Fragment (Android)
// Created: 2025-08-15

package com.signal.playerkit.demo

import android.os.Bundle
import android.view.*
import android.widget.FrameLayout
import androidx.fragment.app.Fragment
import com.google.android.exoplayer2.ui.PlayerView
import com.signal.playerkit.*

data class VideoItem(val id: String, val hlsUrl: String, val durationMs: Long? = null)

class FeedFragment : Fragment() {
    private lateinit var containerView: FrameLayout
    private lateinit var playerView: PlayerView
    private val eventBus: EventBus = HttpEventBus("https://api.example.com/event")
    private lateinit var pool: PlayerPool
    private var items: List<VideoItem> = listOf()
    private var currentIndex = 0
    private var current: ExoPlayerKit? = null
    private var viewStart: Long = 0
    
    override fun onCreateView(inflater: LayoutInflater, parent: ViewGroup?, state: Bundle?): View {
        containerView = FrameLayout(requireContext())
        containerView.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        playerView = PlayerView(requireContext())
        containerView.addView(playerView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        val gd = GestureDetector(requireContext(), object : GestureDetector.SimpleOnGestureListener() {
            private val threshold = 100; private val velocity = 100
            override fun onFling(e1: MotionEvent, e2: MotionEvent, vX: Float, vY: Float): Boolean {
                val diffY = e2.y - e1.y
                if (kotlin.math.abs(diffY) > threshold && kotlin.math.abs(vY) > velocity) {
                    if (diffY < 0) nextClip() else prevClip(); return true
                }
                return false
            }
        })
        containerView.setOnTouchListener { _, ev -> gd.onTouchEvent(ev) }
        return containerView
    }
    
    override fun onViewCreated(view: View, state: Bundle?) {
        super.onViewCreated(view, state)
        pool = PlayerPool(requireContext(), eventBus, 3)
        items = listOf(
            VideoItem("a1", "https://cdn.example.com/vod/a1/master.m3u8"),
            VideoItem("b2", "https://cdn.example.com/vod/b2/master.m3u8"),
            VideoItem("c3", "https://cdn.example.com/vod/c3/master.m3u8")
        )
        startAt(0)
    }
    
    private fun startAt(index: Int) {
        currentIndex = index
        current = pool.acquire()
        current?.onEvent = { name, props -> /* analytics hook */ }
        current?.prepare(items[index].hlsUrl, initialBitrateCapKbps = 700)
        playerView.player = current?.exo()
        current?.play()
        viewStart = System.currentTimeMillis()
        nextIndex()?.let { pool.preloadNext(items[it].hlsUrl) }
    }
    
    private fun nextClip() {
        current?.let { emitViewEnd(items[currentIndex], it) }
        current?.let { pool.release(it) }
        currentIndex = nextIndex() ?: currentIndex
        current = pool.acquire()
        playerView.player = current?.exo()
        current?.play()
        viewStart = System.currentTimeMillis()
        nextIndex()?.let { pool.preloadNext(items[it].hlsUrl) }
    }
    
    private fun prevClip() {
        current?.let { emitViewEnd(items[currentIndex], it) }
        current?.let { pool.release(it) }
        currentIndex = if (currentIndex > 0) currentIndex - 1 else 0
        startAt(currentIndex)
    }
    
    private fun nextIndex(): Int? { val ni = currentIndex + 1; return if (ni in items.indices) ni else null }
    
    private fun emitViewEnd(item: VideoItem, pk: ExoPlayerKit) {
        val dwellMs = System.currentTimeMillis() - viewStart
        val pos = pk.positionMs().toDouble()
        val dur = if (pk.durationMs() > 0) pk.durationMs().toDouble() else 1.0
        val pct = ((pos / dur) * 100.0).toInt()
        eventBus.enqueue(TelemetryEvent("view_end", mapOf("video_id" to item.id, "dwell_ms" to dwellMs, "percent_complete" to pct)))
        eventBus.flushNow()
    }
}
