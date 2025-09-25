package com.example.signal_android

import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions
import androidx.test.espresso.matcher.ViewMatchers.withId
import org.hamcrest.Matchers.allOf
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PoolPerfInstrumentedTest {

    @get:Rule
    val scenarioRule = ActivityScenarioRule(FeedPagerActivity::class.java)

    @Before
    fun setUp() {
        AutomationMetrics.reset()
    }

    @Test
    fun rapidScrollMaintainsBudgets() {
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeUp())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeUp())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeDown())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeUp())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeUp())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeDown())
        onView(withId(R.id.feedPager)).perform(ViewActions.swipeUp())

        Thread.sleep(2000)

        val events = AutomationMetrics.snapshot()
        val ttffValues = events.filter { it.getString("name") == "first_frame" }
            .mapNotNull { propsDouble(it, "ms") }

        assertFalse("No TTFF metrics captured", ttffValues.isEmpty())
        assertTrue("TTFF exceeded budget: $ttffValues", ttffValues.all { it <= 2000 })

        val playbackErrors = events.filter { it.getString("name") == "playback_error" }
        assertTrue("Playback errors observed: $playbackErrors", playbackErrors.isEmpty())
    }

    private fun propsDouble(json: JSONObject, key: String): Double? {
        val props = json.optJSONObject("props") ?: return null
        return when (val value = props.opt(key)) {
            is Number -> value.toDouble()
            is Boolean -> if (value) 1.0 else 0.0
            else -> null
        }
    }
}
