import XCTest

final class FeedPoolingPerfUITests: XCTestCase {
    private var metricsURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        metricsURL = tempDir.appendingPathComponent("automation_metrics_\(UUID().uuidString).jsonl")
        try? FileManager.default.removeItem(at: metricsURL)
    }

    override func tearDownWithError() throws {
        if let url = metricsURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testRapidScrollMaintainsTTFFBudget() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AUTOMATION_METRICS"] = "1"
        app.launchEnvironment["AUTOMATION_METRICS_PATH"] = metricsURL.path
        app.launchArguments.append("AUTOMATION_METRICS")
        app.launch()

        let feed = app.collectionViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 5), "Feed collection should appear")

        // Give the first item a moment to settle, then perform rapid scroll churn.
        feed.swipeUp()
        feed.swipeUp()
        feed.swipeDown()
        feed.swipeUp()
        feed.swipeUp()
        feed.swipeDown()
        feed.swipeUp()

        // Brief pause to allow telemetry to flush.
        sleep(2)
        app.terminate()

        let events = try loadMetrics()
        let ttffValues = events
            .filter { $0.name == "time_to_first_frame" }
            .compactMap { $0.props["ms"]?.doubleValue }

        XCTAssertFalse(ttffValues.isEmpty, "Expected TTFF metrics to be collected")
        XCTAssertTrue(ttffValues.allSatisfy { $0 <= 2_000 }, "TTFF exceeded budget: \(ttffValues)")

        let playbackErrors = events.filter { $0.name == "playback_error" }
        XCTAssertTrue(playbackErrors.isEmpty, "Playback errors observed during pooling perf run: \(playbackErrors)")
    }

    private func loadMetrics() throws -> [AutomationMetricEvent] {
        let data = try Data(contentsOf: metricsURL)
        guard !data.isEmpty else { return [] }
        let content = String(decoding: data, as: UTF8.self)
        let lines = content.split(separator: "\n")
        let decoder = JSONDecoder()
        return try lines.map { try decoder.decode(AutomationMetricEvent.self, from: Data($0.utf8)) }
    }
}

private struct AutomationMetricEvent: Decodable {
    struct MetricValue: Decodable {
        let number: Double?
        let bool: Bool?

        var doubleValue: Double? {
            if let number = number { return number }
            if let bool = bool { return bool ? 1 : 0 }
            return nil
        }
    }

    let name: String
    let timestamp: Int64
    let props: [String: MetricValue]

    private enum CodingKeys: String, CodingKey {
        case name
        case timestamp
        case props
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        timestamp = try container.decode(Int64.self, forKey: .timestamp)

        let propsContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .props)
        var temp: [String: MetricValue] = [:]
        for key in propsContainer.allKeys {
            if let value = try? propsContainer.decode(Double.self, forKey: key) {
                temp[key.stringValue] = MetricValue(number: value, bool: nil)
            } else if let value = try? propsContainer.decode(Int.self, forKey: key) {
                temp[key.stringValue] = MetricValue(number: Double(value), bool: nil)
            } else if let value = try? propsContainer.decode(Bool.self, forKey: key) {
                temp[key.stringValue] = MetricValue(number: nil, bool: value)
            }
        }
        props = temp
    }
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }

    var intValue: Int?
    init?(intValue: Int) { return nil }
}
