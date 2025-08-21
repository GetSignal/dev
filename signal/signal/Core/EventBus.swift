//
//  EventBus.swift
//  signal
//
//  Telemetry event bus with batching and debouncing
//  Specification: batch/debounce ~200ms to /v1/events
//

import Foundation

// MARK: - Event Models
struct TelemetryEvent: Codable {
    let name: String
    var props: [String: AnyCodable]
    let timestamp: Int64
    
    init(name: String, props: [String: AnyCodable] = [:]) {
        self.name = name
        self.props = props
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case _ as NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

struct EventBatch: Codable {
    let deviceId: String
    let sessionId: String
    let ts: Int64
    let events: [TelemetryEvent]
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case sessionId = "session_id"
        case ts
        case events
    }
}

// MARK: - EventBus Protocol
protocol EventBusProtocol {
    func enqueue(_ event: TelemetryEvent)
    func flushNow()
}

// MARK: - EventBus Implementation
class EventBus: EventBusProtocol {
    private let endpoint: URL
    private let deviceId: String
    private let sessionId: String
    private let debounceInterval: TimeInterval = 0.2 // 200ms as per spec
    
    private var eventQueue: [TelemetryEvent] = []
    private let queueLock = NSLock()
    private var debounceTimer: Timer?
    private let session: URLSession
    
    // Testing support
    var isTestMode: Bool = false
    var testModeHandler: ((EventBatch) -> Void)?
    
    init(endpoint: URL, session: URLSession = URLSession.shared) {
        self.endpoint = endpoint
        self.session = session
        self.deviceId = Self.getDeviceId()
        self.sessionId = Self.generateSessionId()
    }
    
    deinit {
        debounceTimer?.invalidate()
        flushNow()
    }
    
    func enqueue(_ event: TelemetryEvent) {
        queueLock.lock()
        eventQueue.append(event)
        queueLock.unlock()
        
        // Reset debounce timer
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimer?.invalidate()
            self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: self?.debounceInterval ?? 0.2, repeats: false) { _ in
                self?.flushNow()
            }
        }
    }
    
    func flushNow() {
        queueLock.lock()
        let eventsToSend = eventQueue
        eventQueue.removeAll()
        queueLock.unlock()
        
        guard !eventsToSend.isEmpty else { return }
        
        let batch = EventBatch(
            deviceId: deviceId,
            sessionId: sessionId,
            ts: Int64(Date().timeIntervalSince1970 * 1000),
            events: eventsToSend
        )
        
        if isTestMode {
            // In test mode, call handler synchronously
            testModeHandler?(batch)
        } else {
            // Normal async operation
            Task {
                await sendBatch(batch)
            }
        }
    }
    
    private func sendBatch(_ batch: EventBatch) async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(batch)
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 400 {
                    print("[EventBus] Failed to send batch: HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[EventBus] Failed to send batch: \(error)")
        }
    }
    
    // MARK: - Helpers
    private static func getDeviceId() -> String {
        if let deviceId = UserDefaults.standard.string(forKey: "signal_device_id") {
            return deviceId
        }
        let deviceId = "ios-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(deviceId, forKey: "signal_device_id")
        return deviceId
    }
    
    private static func generateSessionId() -> String {
        return "s-\(UUID().uuidString.lowercased())"
    }
}

// MARK: - Predefined Events
extension EventBusProtocol {
    func trackViewStart(videoId: String) {
        enqueue(TelemetryEvent(name: "view_start", props: ["video_id": AnyCodable(videoId)]))
    }
    
    func trackViewEnd(videoId: String, dwellMs: Int, percentComplete: Int) {
        enqueue(TelemetryEvent(name: "view_end", props: [
            "video_id": AnyCodable(videoId),
            "dwell_ms": AnyCodable(dwellMs),
            "percent_complete": AnyCodable(percentComplete)
        ]))
    }
    
    func trackTapPlayPause(playing: Bool) {
        enqueue(TelemetryEvent(name: "tap_play_pause", props: ["playing": AnyCodable(playing)]))
    }
    
    func trackPreviewScrubStart() {
        enqueue(TelemetryEvent(name: "preview_scrub_start"))
    }
    
    func trackPreviewScrubCommit(seconds: Double) {
        enqueue(TelemetryEvent(name: "preview_scrub_commit", props: ["seconds": AnyCodable(Int(seconds))]))
    }
    
    func trackTimeToFirstFrame(ms: Int) {
        enqueue(TelemetryEvent(name: "time_to_first_frame", props: ["ms": AnyCodable(ms)]))
    }
    
    func trackRebuffer(count: Int, totalMs: Int) {
        enqueue(TelemetryEvent(name: "rebuffer", props: [
            "count": AnyCodable(count),
            "total_ms": AnyCodable(totalMs)
        ]))
    }
    
    func trackSelectedBitrate(kbps: Int) {
        enqueue(TelemetryEvent(name: "selected_bitrate", props: ["kbps": AnyCodable(kbps)]))
    }
    
    func trackPlaybackError(videoId: String, code: String) {
        enqueue(TelemetryEvent(name: "playback_error", props: [
            "video_id": AnyCodable(videoId),
            "code": AnyCodable(code)
        ]))
    }
}