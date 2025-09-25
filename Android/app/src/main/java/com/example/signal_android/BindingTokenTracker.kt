package com.example.signal_android

import java.util.concurrent.atomic.AtomicLong

class BindingTokenTracker {
    private val generator = AtomicLong(0)
    @Volatile
    private var current: Long = 0

    fun next(): Long {
        val value = generator.incrementAndGet()
        current = value
        return value
    }

    fun update(token: Long) {
        current = token
    }

    fun matches(token: Long): Boolean = token != 0L && token == current

    fun clear() {
        current = 0
    }

    fun snapshot(): Long = current
}
