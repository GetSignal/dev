package com.example.signal_android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BindingTokenTest {

    @Test
    fun `tracker matches current token and rejects stale ones`() {
        val tracker = BindingTokenTracker()
        val first = tracker.next()
        assertTrue(tracker.matches(first))

        val second = tracker.next()
        assertFalse(tracker.matches(first))
        assertTrue(tracker.matches(second))

        tracker.clear()
        assertFalse(tracker.matches(second))
    }
}
