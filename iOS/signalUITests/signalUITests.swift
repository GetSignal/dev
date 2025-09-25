//
//  signalUITests.swift
//  signalUITests
//
//  Created by Abiola Samuel on 8/19/25.
//

import XCTest

final class signalUITests: XCTestCase {
    
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        
        // Add timeout handling for UI tests
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        
        // Launch with timeout
        app.launch()
        
        // Wait for accessibility services to be ready
        let launched = app.wait(for: .runningForeground, timeout: 10)
        XCTAssertTrue(launched, "App should launch within 10 seconds")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Paging Tests
    
    @MainActor
    func testVerticalSwipeNavigation() throws {
        // Wait for app to fully load - look for any element that indicates content
        let contentLoaded = app.windows.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(contentLoaded, "App content should load")
        
        // Give app time to initialize video content
        Thread.sleep(forTimeInterval: 2)
        
        // Perform swipe gestures on the main window
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        
        // Swipe up to next video
        mainWindow.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Swipe down to previous video
        mainWindow.swipeDown()
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(mainWindow.exists, "App should remain responsive after swiping")
    }
    
    @MainActor
    func testMultipleSwipeNavigation() throws {
        let contentLoaded = app.windows.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(contentLoaded, "App content should load")
        
        Thread.sleep(forTimeInterval: 2)
        let mainWindow = app.windows.firstMatch
        
        // Perform multiple swipes up
        for _ in 0..<3 {
            mainWindow.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // Swipe back down
        for _ in 0..<3 {
            mainWindow.swipeDown()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        XCTAssertTrue(mainWindow.exists, "App should remain responsive after multiple swipes")
    }
    
    // MARK: - Gesture Tests
    
    @MainActor
    func testTapToPlayPause() throws {
        let contentLoaded = app.windows.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(contentLoaded, "App content should load")
        
        Thread.sleep(forTimeInterval: 2)
        let mainWindow = app.windows.firstMatch
        
        // Tap to pause (assuming autoplay is on)
        mainWindow.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Tap again to play
        mainWindow.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(mainWindow.exists, "App should respond to tap gestures")
    }
    
    @MainActor
    func testLongPressForScrubbing() throws {
        let contentLoaded = app.windows.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(contentLoaded, "App content should load")
        
        Thread.sleep(forTimeInterval: 2)
        let mainWindow = app.windows.firstMatch
        
        // Perform long press and drag for scrubbing
        let startCoordinate = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let endCoordinate = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        
        startCoordinate.press(forDuration: 0.5, thenDragTo: endCoordinate)
        
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(mainWindow.exists, "App should respond to long press and drag gestures")
    }
    
    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    @MainActor
    func testScrollingPerformance() throws {
        let feedExists = app.otherElements.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(feedExists)
        
        measure {
            for _ in 0..<5 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
}
