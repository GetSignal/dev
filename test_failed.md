# EventBus Test Failure Analysis

## Overview
Three systematic attempts were made to fix EventBus test failures in the Signal iOS project. All attempts failed due to fundamental misunderstanding of the async/timer interaction in test environments.

## Failing Tests
- `EventBusTests.testDebouncing()`
- `EventBusTests.testEventBatching()`  
- `EventBusTests.testFlushNow()` (fixed in Attempt 3)

## Agent Guide Requirements
The Signal Agent Guide explicitly requires **"Tests pass"** as acceptance criteria for Phase 1 compliance. The EventBus implements 200ms debouncing for batching telemetry events as specified.

---

## Attempt 1: URLSession Dependency Injection + Timing Adjustments

### Date
2025-08-21 (First attempt)

### Approach
- **Root Cause Hypothesis**: Test mocking wasn't working because EventBus used `URLSession.shared`
- **Solution**: Inject custom URLSession with MockURLProtocol into EventBus constructor
- **Test Strategy**: Increase timeouts and add better error messages

### Implementation Details
```swift
// Added URLSession parameter to EventBus init
init(endpoint: URL, session: URLSession = URLSession.shared) {
    self.session = session
    // ...
}

// Modified test setup with MockURLProtocol
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let mockSession = URLSession(configuration: config)
eventBus = EventBus(endpoint: url, session: mockSession)
```

### Test Results
- `testFlushNow()` ❌ Still failed
- `testEventBatching()` ❌ Still failed  
- `testDebouncing()` ❌ Still failed (3.8s timeout)
- UI tests ✅ Fixed successfully

### Why It Failed
**Fundamental Issue**: The problem wasn't URL mocking - it was that the `Task { await sendBatch() }` runs asynchronously, and tests complete before the async network request finishes. Even with proper mocking, the timing was still non-deterministic.

---

## Attempt 2: Completion Handler Pattern

### Date
2025-08-21 (Second attempt)

### Approach
- **Root Cause Hypothesis**: Async Task completion wasn't being awaited in tests
- **Solution**: Add completion callback to EventBus for test synchronization
- **Test Strategy**: Use XCTestExpectation with completion handlers

### Implementation Details
```swift
// Added to EventBus
var flushCompletion: (() -> Void)?

// Modified sendBatch to call completion
Task {
    await sendBatch(batch)
    await MainActor.run {
        self.flushCompletion?()
    }
}

// Updated test pattern
eventBus.flushCompletion = { [weak self] in
    // Verify results here
    expectation.fulfill()
}
```

### Test Results
- `testFlushNow()` ❌ Still failed
- `testEventBatching()` ❌ Still failed
- `testDebouncing()` ❌ Still failed (3.8s timeout)
- UI tests ✅ Remained fixed

### Why It Failed
**Fundamental Issue**: The completion handler approach still relied on the debounce Timer firing, which is asynchronous. The tests were still racing against timer execution, and the callbacks weren't being invoked because the timers weren't completing within the test timeframe.

---

## Attempt 3: Test Mode with Synchronous Handler

### Date
2025-08-21 (Third attempt)

### Approach
- **Root Cause Hypothesis**: All async behavior needs to be bypassed in tests
- **Solution**: Add `isTestMode` flag to make EventBus completely synchronous during testing
- **Test Strategy**: Synchronous test handler + Thread.sleep for debouncing

### Implementation Details
```swift
// Added test mode to EventBus
var isTestMode: Bool = false
var testModeHandler: ((EventBatch) -> Void)?

// Modified flushNow for test mode
if isTestMode {
    testModeHandler?(batch)  // Synchronous call
} else {
    Task { await sendBatch(batch) }  // Normal async
}

// Test setup
eventBus.isTestMode = true
eventBus.testModeHandler = { [weak self] batch in
    // Create fake URLRequest and capture
    self?.capturedRequests.append(request)
}
```

### Test Results
- `testFlushNow()` ✅ **PASSED** (0.004s) - Synchronous flush works!
- `testEventBatching()` ❌ Still failed (0.260s)
- `testDebouncing()` ❌ Still failed (1.504s)
- UI tests ✅ Remained fixed

### Why It Failed
**Fundamental Issue**: Even with test mode, the debouncing still relies on Timer, which schedules on the main run loop. `Thread.sleep()` blocks the current thread but doesn't pump the run loop, so timers never fire. The tests were waiting for debounce timers that would never execute.

---

## Core Problem Analysis

### The Real Issue
All three attempts missed the fundamental problem: **Timer-based debouncing is incompatible with Thread.sleep() in unit tests**.

```swift
// This schedules a timer on main run loop
Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
    self?.flushNow()
}

// This blocks the thread but doesn't run the run loop
Thread.sleep(forTimeInterval: 0.25)  // Timer never fires!
```

### Why Tests Fail
1. **Event is queued** → Timer scheduled for 200ms later
2. **Test calls Thread.sleep(0.25)** → Thread blocked, run loop doesn't run  
3. **Timer never fires** → No batch sent, no requests captured
4. **Test assertion fails** → `capturedRequests.count == 0` instead of `1`

### Why testFlushNow() Succeeded in Attempt 3
Because `flushNow()` bypasses the debounce timer entirely and calls the test handler immediately.

---

## Lessons Learned

### What Doesn't Work
- ❌ **URLSession mocking alone** - Doesn't address async timing
- ❌ **Completion handler callbacks** - Still relies on timer execution  
- ❌ **Thread.sleep() with timers** - Blocks run loop, timers never fire
- ❌ **Partial test mode** - Must eliminate ALL async behavior for deterministic tests

### What Works
- ✅ **Synchronous flush** - Direct method calls work immediately
- ✅ **Complete test mode** - Bypassing all async behavior
- ✅ **UI test improvements** - Proper element selection and timeouts

### Required Solution
The debounce mechanism itself must be made testable:
- Either replace Timer with something controllable
- Or provide test-mode override that bypasses debouncing entirely  
- Or use RunLoop.main.run(until:) instead of Thread.sleep()

---

## Impact on Phase 1 Compliance

### Current Status: ❌ FAILED
- **Required**: "Tests pass" (Agent Guide)
- **Reality**: 2 out of 5 EventBus tests still failing
- **Blocker**: Phase 1 cannot be marked complete until EventBus tests pass

### What's Working
- ✅ VTT parsing tests (5/5 passing)
- ✅ UI tests (6/6 passing) 
- ✅ EventBus basic functionality (2/5 passing)

### Next Steps Required
A fourth attempt must address the Timer/RunLoop interaction directly, not work around it.