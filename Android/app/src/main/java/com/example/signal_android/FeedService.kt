package com.example.signal_android

import android.content.Context
import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Cache
import okhttp3.Request
import android.util.Log
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class FeedService(context: Context) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(3, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        // Enable disk cache so manifests and feed responses honor CDN Cache-Control
        .cache(Cache(File(context.cacheDir, "signal-http-cache"), 32L * 1024L * 1024L))
        .apply {
            if (BuildConfig.DEBUG) {
                addInterceptor { chain ->
                    val req = chain.request()
                    val res = chain.proceed(req)
                    val src = when {
                        res.cacheResponse != null -> "CACHE"
                        res.networkResponse != null -> "NETWORK"
                        else -> "UNKNOWN"
                    }
                    Log.d("HTTP", "${req.method} ${req.url} -> $src ${res.code}")
                    res
                }
            }
        }
        .build()
    private val bg = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val baseUrl: String = BuildConfig.API_BASE_URL

    fun fetchFeed(onResult: (List<VideoItem>?, Throwable?) -> Unit) {
        bg.execute {
            try {
                val feedReq = Request.Builder().url("$baseUrl/v1/feed").build()
                client.newCall(feedReq).execute().use { resp ->
                    if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
                    val txt = resp.body?.string() ?: throw IOException("empty body")
                    val root = JSONObject(txt)
                    val items = root.getJSONArray("items")
                    val out = mutableListOf<VideoItem>()
                    for (i in 0 until items.length()) {
                        val it = items.getJSONObject(i)
                        val id = it.optString("video_id")
                        val manifestUrl = it.optString("media_manifest_url")
                        val manifest = fetchManifest(manifestUrl)
                        val hls = manifest.optString("hls_url")
                        val vtt = manifest.optString("thumbnail_vtt_url", null)
                        if (hls.isNotBlank()) {
                            out += VideoItem(id, hls, durationMs = manifest.optLong("duration_ms", 0L), thumbnailHint = vtt)
                        }
                    }
                    main.post { onResult(out, null) }
                }
            } catch (t: Throwable) {
                main.post { onResult(null, t) }
            }
        }
    }

    private fun fetchManifest(url: String): JSONObject {
        val req = Request.Builder().url(url).build()
        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code}")
            val txt = resp.body?.string() ?: throw IOException("empty manifest body")
            return JSONObject(txt)
        }
    }
}
