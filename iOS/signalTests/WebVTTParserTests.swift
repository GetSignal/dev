//
//  WebVTTParserTests.swift
//  signalTests
//
//  Unit tests for WebVTT parser
//

import XCTest
@testable import signal

final class WebVTTParserTests: XCTestCase {
    
    func testParseValidVTT() {
        let vttContent = """
        WEBVTT
        
        00:00:00.000 --> 00:00:02.000
        sprite.jpg#xywh=0,0,160,90
        
        00:00:02.000 --> 00:00:04.000
        sprite.jpg#xywh=160,0,160,90
        
        00:00:04.000 --> 00:00:06.000
        sprite.jpg#xywh=320,0,160,90
        """
        
        let baseUrl = URL(string: "https://cdn.example.com/storyboard/")!
        let cues = WebVTTParser.parse(vttContent: vttContent, baseUrl: baseUrl)
        
        XCTAssertEqual(cues.count, 3)
        
        // Test first cue
        XCTAssertEqual(cues[0].startTime, 0.0)
        XCTAssertEqual(cues[0].endTime, 2.0)
        XCTAssertEqual(cues[0].rect, CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(cues[0].imageUrl.absoluteString, "https://cdn.example.com/storyboard/sprite.jpg")
        
        // Test second cue
        XCTAssertEqual(cues[1].startTime, 2.0)
        XCTAssertEqual(cues[1].endTime, 4.0)
        XCTAssertEqual(cues[1].rect, CGRect(x: 160, y: 0, width: 160, height: 90))
        
        // Test third cue
        XCTAssertEqual(cues[2].startTime, 4.0)
        XCTAssertEqual(cues[2].endTime, 6.0)
        XCTAssertEqual(cues[2].rect, CGRect(x: 320, y: 0, width: 160, height: 90))
    }
    
    func testParseTimeFormats() {
        let vttContent = """
        WEBVTT
        
        01:30:45.500 --> 01:30:47.500
        sprite.jpg#xywh=0,0,160,90
        
        30:45.500 --> 30:47.500
        sprite.jpg#xywh=160,0,160,90
        """
        
        let cues = WebVTTParser.parse(vttContent: vttContent)
        
        XCTAssertEqual(cues.count, 2)
        
        // Test HH:MM:SS.mmm format
        XCTAssertEqual(cues[0].startTime, 5445.5) // 1h 30m 45.5s
        XCTAssertEqual(cues[0].endTime, 5447.5)
        
        // Test MM:SS.mmm format
        XCTAssertEqual(cues[1].startTime, 1845.5) // 30m 45.5s
        XCTAssertEqual(cues[1].endTime, 1847.5)
    }
    
    func testFindCue() {
        let cues = [
            VTTCue(startTime: 0, endTime: 2, imageUrl: URL(string: "https://cdn.example.com/sprite.jpg")!, rect: CGRect(x: 0, y: 0, width: 160, height: 90)),
            VTTCue(startTime: 2, endTime: 4, imageUrl: URL(string: "https://cdn.example.com/sprite.jpg")!, rect: CGRect(x: 160, y: 0, width: 160, height: 90)),
            VTTCue(startTime: 4, endTime: 6, imageUrl: URL(string: "https://cdn.example.com/sprite.jpg")!, rect: CGRect(x: 320, y: 0, width: 160, height: 90))
        ]
        
        // Test finding cues at different times
        XCTAssertNotNil(WebVTTParser.findCue(at: 0.5, in: cues))
        XCTAssertEqual(WebVTTParser.findCue(at: 0.5, in: cues)?.rect.origin.x, 0)
        
        XCTAssertNotNil(WebVTTParser.findCue(at: 2.5, in: cues))
        XCTAssertEqual(WebVTTParser.findCue(at: 2.5, in: cues)?.rect.origin.x, 160)
        
        XCTAssertNotNil(WebVTTParser.findCue(at: 5.5, in: cues))
        XCTAssertEqual(WebVTTParser.findCue(at: 5.5, in: cues)?.rect.origin.x, 320)
        
        // Test edge cases
        XCTAssertNotNil(WebVTTParser.findCue(at: 0, in: cues))
        XCTAssertNotNil(WebVTTParser.findCue(at: 2, in: cues))
        XCTAssertNil(WebVTTParser.findCue(at: 6, in: cues)) // Exactly at end
        XCTAssertNil(WebVTTParser.findCue(at: 10, in: cues)) // Beyond range
    }
    
    func testInvalidVTT() {
        let invalidContent = """
        Invalid content
        without proper format
        """
        
        let cues = WebVTTParser.parse(vttContent: invalidContent)
        XCTAssertEqual(cues.count, 0)
    }
    
    func testEmptyVTT() {
        let cues = WebVTTParser.parse(vttContent: "")
        XCTAssertEqual(cues.count, 0)
    }
}