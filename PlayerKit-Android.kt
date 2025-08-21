// PlayerKit-Android.kt
// Signal Video — PlayerKit (Android)
// Created: 2025-08-15
package com.signal.playerkit

import android.content.Context
import android.net.Uri
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.upstream.DefaultDataSource
import com.google.android.exoplayer2.util.MimeTypes
import com.google.android.exoplayer2.analytics.AnalyticsListener
import okhttp3.*
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

interface EventBus { fun enqueue(event: TelemetryEvent); fun flushNow() }
data class TelemetryEvent(val name: String, val props: Map<String, Any?> = emptyMap(), val ts: Long = System.currentTimeMillis())

class HttpEventBus(
    private val endpoint: String, private val apiKey: String? = null, private val userId: String? = null,
    flushIntervalSec: Long = 3, private val maxBatch: Int = 25
) : EventBus {
    private val client = OkHttpClient.Builder().connectTimeout(3, TimeUnit.SECONDS).build()
    private val buffer = mutableListOf<TelemetryEvent>()
    private val lock = Any()
    init { Thread { while (true) { Thread.sleep(flushIntervalSec * 1000); flushNow() } }.apply { isDaemon = true }.start() }
    override fun enqueue(event: TelemetryEvent) { synchronized(lock) { buffer.add(event); if (buffer.size >= maxBatch) flushNow() } }
    override fun flushNow() {
        val batch: List<TelemetryEvent>
        synchronized(lock) { if (buffer.isEmpty()) return; batch = buffer.toList(); buffer.clear() }
        val arr = JSONArray(); batch.forEach { e -> val obj = JSONObject(); obj.put("name", e.name); obj.put("props", JSONObject(e.props)); obj.put("ts", e.ts); arr.put(obj) }
        val root = JSONObject(); root.put("events", arr); userId?.let { root.put("user_id", it) }
        val req = Request.Builder().url(endpoint).post(RequestBody.create("application/json".toMediaTypeOrNull(), root.toString()))
            .apply { apiKey?.let { addHeader("X-API-Key", it) } }.build()
        client.newCall(req).enqueue(object: Callback { override fun onFailure(call: Call, e: java.io.IOException) {} ; override fun onResponse(call: Call, response: Response) { response.close() } })
    }
}

interface PlayerKit {
    fun prepare(hlsUrl: String, initialBitrateCapKbps: Int? = null)
    fun play(); fun pause(); fun seek(ms: Long); fun dispose()
    var onEvent: ((name: String, props: Map<String, Any?>) -> Unit)?
    fun exo(): ExoPlayer
    fun positionMs(): Long
    fun durationMs(): Long
}

class ExoPlayerKit(private val context: Context, private val eventBus: EventBus) : PlayerKit {
    private val trackSelector = DefaultTrackSelector(context)
    private val player = ExoPlayer.Builder(context).setTrackSelector(trackSelector).build()
    private var preparedAt: Long = 0L
    override var onEvent: ((name: String, props: Map<String, Any?>) -> Unit)? = null
    private val analyticsListener = object : AnalyticsListener {
        override fun onRenderedFirstFrame(eventTime: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
            val tff = System.currentTimeMillis() - preparedAt
            onEvent?.invoke("first_frame", mapOf("ms" to tff)); eventBus.enqueue(TelemetryEvent("first_frame", mapOf("ms" to tff)))
        }
        override fun onPlaybackStateChanged(eventTime: AnalyticsListener.EventTime, state: Int) {
            when (state) {
                Player.STATE_BUFFERING -> { onEvent?.invoke("rebuffer_start", emptyMap()); eventBus.enqueue(TelemetryEvent("rebuffer_start")) }
                Player.STATE_READY -> { onEvent?.invoke("rebuffer_end", emptyMap()); eventBus.enqueue(TelemetryEvent("rebuffer_end")) }
                Player.STATE_ENDED -> { onEvent?.invoke("ended", emptyMap()); eventBus.enqueue(TelemetryEvent("ended")) }
            }
        }
        override fun onDownstreamFormatChanged(eventTime: AnalyticsListener.EventTime, mediaLoadData: MediaLoadData) {
            if (mediaLoadData.trackType == C.TRACK_TYPE_VIDEO && mediaLoadData.trackFormat != null) {
                val height = mediaLoadData.trackFormat.height; val br = mediaLoadData.trackFormat.bitrate
                onEvent?.invoke("bitrate_change", mapOf("bitrate" to br, "height" to height))
                eventBus.enqueue(TelemetryEvent("bitrate_change", mapOf("bitrate" to br, "height" to height)))
            }
        }
    }
    init { player.addAnalyticsListener(analyticsListener) }
    override fun prepare(hlsUrl: String, initialBitrateCapKbps: Int?) {
        preparedAt = System.currentTimeMillis()
        initialBitrateCapKbps?.let { trackSelector.parameters = trackSelector.buildUponParameters().setMaxVideoBitrate(it * 1000).build() }
        val mediaSource = buildHlsSource(hlsUrl); player.setMediaSource(mediaSource); player.prepare()
        onEvent?.invoke("prepared", mapOf("url" to hlsUrl)); eventBus.enqueue(TelemetryEvent("prepared", mapOf("url" to hlsUrl)))
    }
    override fun play() { player.playWhenReady = true; onEvent?.invoke("playback_start", emptyMap()); eventBus.enqueue(TelemetryEvent("playback_start")) }
    override fun pause() { player.playWhenReady = false; onEvent?.invoke("paused", emptyMap()); eventBus.enqueue(TelemetryEvent("paused")) }
    override fun seek(ms: Long) { player.seekTo(ms); onEvent?.invoke("seek", mapOf("ms" to ms)); eventBus.enqueue(TelemetryEvent("seek", mapOf("ms" to ms))) }
    override fun dispose() { player.release(); onEvent?.invoke("disposed", emptyMap()) }
    private fun buildHlsSource(url: String): MediaSource {
        val dsFactory = DefaultDataSource.Factory(context)
        return HlsMediaSource.Factory(dsFactory).setAllowChunklessPreparation(true)
            .createMediaSource(MediaItem.Builder().setUri(Uri.parse(url)).setMimeType(MimeTypes.APPLICATION_M3U8).build())
    }
    override fun exo(): ExoPlayer = player
    override fun positionMs(): Long = player.currentPosition
    override fun durationMs(): Long = if (player.duration > 0) player.duration else 0L
}

class PlayerPool(private val context: Context, private val eventBus: EventBus, private val size: Int = 3) {
    private val pool: ArrayDeque<ExoPlayerKit> = ArrayDeque<ExoPlayerKit>().apply { repeat(maxOf(2, size)) { add(ExoPlayerKit(context, eventBus)) } }
    fun acquire(): ExoPlayerKit = pool.removeFirst()
    fun release(player: ExoPlayerKit) { pool.addLast(player) }
    fun preloadNext(hlsUrl: String) { val p = pool.firstOrNull() ?: return; p.prepare(hlsUrl, initialBitrateCapKbps = 700); eventBus.enqueue(TelemetryEvent("preload_started", mapOf("url" to hlsUrl))) }
}
