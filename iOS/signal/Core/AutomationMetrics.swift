//
//  AutomationMetrics.swift
//  signal
//
//  Collects playback telemetry during UI automation runs so tests can assert
//  TTFF and stall budgets without touching production code paths.
//

import Foundation

final class AutomationMetrics {
    static let shared = AutomationMetrics()
    static let isEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        if let flag = env["AUTOMATION_METRICS"], ["1", "true", "yes"].contains(flag.lowercased()) {
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("AUTOMATION_METRICS") {
            return true
        }
        return false
    }()

    private let queue = DispatchQueue(label: "automation.metrics.queue", qos: .utility)
    private var events: [TelemetryEvent] = []
    private let encoder = JSONEncoder()
    private let fileURL: URL?

    private init() {
        if Self.isEnabled, let path = ProcessInfo.processInfo.environment["AUTOMATION_METRICS_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            fileURL = url
            // Ensure the file exists and is empty before we start writing.
            FileManager.default.createFile(atPath: url.path, contents: nil)
        } else {
            fileURL = nil
        }
    }

    static func record(_ event: TelemetryEvent) {
        guard isEnabled else { return }
        shared.queue.async {
            shared.events.append(event)
            shared.appendToFile(event)
        }
    }

    static func reset() {
        guard isEnabled else { return }
        shared.queue.sync {
            shared.events.removeAll(keepingCapacity: false)
            if let url = shared.fileURL {
                try? Data().write(to: url, options: .atomic)
            }
        }
    }

    static func snapshot() -> [TelemetryEvent] {
        guard isEnabled else { return [] }
        return shared.queue.sync { shared.events }
    }

    private func appendToFile(_ event: TelemetryEvent) {
        guard let url = fileURL else { return }
        guard let data = try? encoder.encode(event) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}
