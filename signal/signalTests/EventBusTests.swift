//
//  EventBusTests.swift
//  signalTests
//
//  Unit tests for EventBus batching and debouncing
//

import XCTest
@testable import signal

// MockURLProtocol removed - using test mode instead

final class EventBusTests: XCTestCase {
    
    var eventBus: EventBus!
    var capturedRequests: [URLRequest] = []
    
    override func setUp() {
        super.setUp()
        
        capturedRequests = []
        
        eventBus = EventBus(
            endpoint: URL(string: "https://api.example.com/v1/events")!
        )
        
        // Enable test mode for synchronous operation
        eventBus.isTestMode = true
        eventBus.testModeHandler = { [weak self] batch in
            // Create a fake request to capture
            var request = URLRequest(url: URL(string: "https://api.example.com/v1/events")!)
            request.httpMethod = "POST"
            request.httpBody = try? JSONEncoder().encode(batch)
            self?.capturedRequests.append(request)
        }
    }
    
    override func tearDown() {
        eventBus?.testModeHandler = nil
        eventBus = nil
        super.tearDown()
    }
    
    func testEventBatching() {
        // Enqueue multiple events
        eventBus.trackViewStart(videoId: "video1")
        eventBus.trackTapPlayPause(playing: true)
        eventBus.trackTimeToFirstFrame(ms: 500)
        
        // Wait for debounce interval
        Thread.sleep(forTimeInterval: 0.25)
        
        // Check results
        XCTAssertEqual(capturedRequests.count, 1, "Events should be batched into single request")
        
        if let request = capturedRequests.first,
           let body = request.httpBody {
            do {
                let batch = try JSONDecoder().decode(EventBatch.self, from: body)
                XCTAssertEqual(batch.events.count, 3, "Batch should contain 3 events")
                XCTAssertEqual(batch.events[0].name, "view_start")
                XCTAssertEqual(batch.events[1].name, "tap_play_pause")
                XCTAssertEqual(batch.events[2].name, "time_to_first_frame")
            } catch {
                XCTFail("Failed to decode batch: \(error)")
            }
        } else {
            XCTFail("No request captured or no body found")
        }
    }
    
    func testDebouncing() {
        // Rapidly enqueue events
        for i in 0..<5 {
            eventBus.trackViewStart(videoId: "video\(i)")
            Thread.sleep(forTimeInterval: 0.05) // 50ms between events
        }
        
        // Wait for debounce to complete after last event
        Thread.sleep(forTimeInterval: 0.25)
        
        // Check results - should be single batch with all events
        XCTAssertEqual(capturedRequests.count, 1, "Rapid events should be debounced into single request")
        
        if let request = capturedRequests.first,
           let body = request.httpBody {
            do {
                let batch = try JSONDecoder().decode(EventBatch.self, from: body)
                XCTAssertEqual(batch.events.count, 5, "All events should be in single batch")
            } catch {
                XCTFail("Failed to decode batch: \(error)")
            }
        } else {
            XCTFail("No request captured or no body found")
        }
    }
    
    func testFlushNow() {
        eventBus.trackViewEnd(videoId: "video1", dwellMs: 1000, percentComplete: 50)
        eventBus.trackRebuffer(count: 2, totalMs: 500)
        
        // Immediately flush without waiting for debounce
        eventBus.flushNow()
        
        // Check results immediately - no waiting needed
        XCTAssertEqual(capturedRequests.count, 1, "FlushNow should send immediately")
        
        if let request = capturedRequests.first,
           let body = request.httpBody {
            do {
                let batch = try JSONDecoder().decode(EventBatch.self, from: body)
                XCTAssertEqual(batch.events.count, 2)
                XCTAssertEqual(batch.events[0].name, "view_end")
                XCTAssertEqual(batch.events[1].name, "rebuffer")
            } catch {
                XCTFail("Failed to decode batch: \(error)")
            }
        } else {
            XCTFail("No request captured or no body found")
        }
    }
    
    func testEventProperties() {
        let expectation = XCTestExpectation(description: "Event properties are correctly encoded")
        
        eventBus.trackViewEnd(videoId: "test_video", dwellMs: 5000, percentComplete: 75)
        eventBus.trackSelectedBitrate(kbps: 1200)
        eventBus.trackPlaybackError(videoId: "test_video", code: "E_HLS_404")
        
        eventBus.flushNow()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let request = self?.capturedRequests.first,
               let body = request.httpBody {
                do {
                    let batch = try JSONDecoder().decode(EventBatch.self, from: body)
                    
                    // Check view_end event
                    let viewEndEvent = batch.events[0]
                    XCTAssertEqual(viewEndEvent.props["video_id"]?.value as? String, "test_video")
                    XCTAssertEqual(viewEndEvent.props["dwell_ms"]?.value as? Int, 5000)
                    XCTAssertEqual(viewEndEvent.props["percent_complete"]?.value as? Int, 75)
                    
                    // Check selected_bitrate event
                    let bitrateEvent = batch.events[1]
                    XCTAssertEqual(bitrateEvent.props["kbps"]?.value as? Int, 1200)
                    
                    // Check playback_error event
                    let errorEvent = batch.events[2]
                    XCTAssertEqual(errorEvent.props["video_id"]?.value as? String, "test_video")
                    XCTAssertEqual(errorEvent.props["code"]?.value as? String, "E_HLS_404")
                    
                } catch {
                    XCTFail("Failed to decode batch: \(error)")
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func testBatchStructure() {
        let expectation = XCTestExpectation(description: "Batch has correct structure")
        
        eventBus.trackPreviewScrubStart()
        eventBus.trackPreviewScrubCommit(seconds: 42.5)
        
        eventBus.flushNow()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let request = self?.capturedRequests.first,
               let body = request.httpBody {
                do {
                    let batch = try JSONDecoder().decode(EventBatch.self, from: body)
                    
                    XCTAssertFalse(batch.deviceId.isEmpty, "Device ID should be set")
                    XCTAssertTrue(batch.deviceId.hasPrefix("ios-"), "Device ID should have iOS prefix")
                    XCTAssertFalse(batch.sessionId.isEmpty, "Session ID should be set")
                    XCTAssertTrue(batch.sessionId.hasPrefix("s-"), "Session ID should have correct prefix")
                    XCTAssertGreaterThan(batch.ts, 0, "Timestamp should be set")
                    
                } catch {
                    XCTFail("Failed to decode batch: \(error)")
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 0.5)
    }
}