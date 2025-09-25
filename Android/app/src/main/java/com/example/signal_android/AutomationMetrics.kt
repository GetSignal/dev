package com.example.signal_android

import org.json.JSONObject
import java.io.File
import java.io.FileWriter
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

object AutomationMetrics {
    private val isEnabled: Boolean = BuildConfig.AUTOMATION_METRICS
    private val events = CopyOnWriteArrayList<JSONObject>()
    private val filePath = System.getenv("AUTOMATION_METRICS_PATH")

    private val executor = Executors.newSingleThreadExecutor()

    fun record(name: String, props: Map<String, Any?> = emptyMap()) {
        if (!isEnabled) return
        val json = JSONObject()
        json.put("name", name)
        json.put("ts", System.currentTimeMillis())
        val propsJson = JSONObject()
        props.forEach { (key, value) -> propsJson.put(key, value) }
        json.put("props", propsJson)
        events += json
        writeToFile(json)
    }

    fun reset() {
        if (!isEnabled) return
        events.clear()
        filePath?.let { path -> File(path).writeText("") }
    }

    fun snapshot(): List<JSONObject> = if (isEnabled) events.toList() else emptyList()

    private fun writeToFile(json: JSONObject) {
        val path = filePath ?: return
        executor.execute {
            FileWriter(path, true).use { writer ->
                writer.append(json.toString())
                writer.append('\n')
            }
        }
    }
}
