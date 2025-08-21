// PlayerKit-iOS.swift
// Signal Video — PlayerKit (iOS)
// Created: 2025-08-15
// Swift 5+, iOS 14+
//
// AVPlayer wrapper with:
// - Player pooling (2–3 instances)
// - Preload policy: fully buffer current, ~5–8s of next
// - Telemetry hooks batched to your event bus (/event API)
// - Simple view attachment + position/duration helpers

import Foundation
import AVFoundation
import UIKit
import ObjectiveC

public protocol EventBus { func enqueue(_ event: TelemetryEvent); func flushNow() }

public struct TelemetryEvent: Codable {
    public let name: String
    public var props: [String: AnyCodable] = [:]
    public let ts: Int64
    public init(name: String, props: [String: AnyCodable] = [:], ts: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.name = name; self.props = props; self.ts = ts
    }
}

public struct AnyCodable: Codable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let b = try? c.decode(Bool.self) { value = b; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if c.decodeNil() { value = NSNull(); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported type")
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let b as Bool: try c.encode(b)
        case let s as String: try c.encode(s)
        case _ as NSNull: try c.encodeNil()
        default:
            let ctx = EncodingError.Context(codingPath: c.codingPath, debugDescription: "Unsupported type")
            throw EncodingError.invalidValue(value, ctx)
        }
    }
}

public final class HttpEventBus: EventBus {
    private var buffer: [TelemetryEvent] = []
    private let queue = DispatchQueue(label: "eventbus.queue", qos: .utility)
    private let session = URLSession(configuration: .ephemeral)
    private let endpoint: URL
    private let flushInterval: TimeInterval
    private var timer: Timer?
    private let maxBatch = 25
    private let apiKey: String?
    private let userId: String?
    public init(endpoint: URL, flushInterval: TimeInterval = 3.0, apiKey: String? = nil, userId: String? = nil) {
        self.endpoint = endpoint; self.flushInterval = flushInterval; self.apiKey = apiKey; self.userId = userId
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in self?.flushNow() }
        }
    }
    public func enqueue(_ event: TelemetryEvent) { queue.async { self.buffer.append(event); if self.buffer.count >= self.maxBatch { self.flushNow() } } }
    public func flushNow() {
        queue.async {
            guard !self.buffer.isEmpty else { return }
            let batch = self.buffer; self.buffer.removeAll(keepingCapacity: true)
            var req = URLRequest(url: self.endpoint); req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = self.apiKey { req.setValue(key, forHTTPHeaderField: "X-API-Key") }
            var payload: [String: Any] = ["events": batch.map { ["name": $0.name, "props": $0.props, "ts": $0.ts] }]
            if let uid = self.userId { payload["user_id"] = uid }
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
            self.session.dataTask(with: req).resume()
        }
    }
}

public protocol PlayerKit: AnyObject {
    func prepare(hlsUrl: URL, initialBitrateCapKbps: Int?)
    func play(); func pause(); func seek(ms: Int64); func dispose()
    var onEvent: ((String, [String: Any]) -> Void)? { get set }
    func attach(to view: UIView)
    var positionSeconds: Double { get }
    var durationSeconds: Double { get }
}

public final class AVPlayerKit: NSObject, PlayerKit {
    private let player = AVPlayer()
    private var itemObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var timeObserver: Any?
    private var startTs: CFAbsoluteTime = 0
    private var firstFrameEmitted = false
    private let eventBus: EventBus
    private weak var attachedView: UIView?
    private var playerLayer: AVPlayerLayer?
    public var preferredForwardBufferDuration: TimeInterval = 8
    public var onEvent: ((String, [String: Any]) -> Void)?
    
    public init(eventBus: EventBus) { self.eventBus = eventBus; super.init(); player.automaticallyWaitsToMinimizeStalling = true }
    
    public func prepare(hlsUrl: URL, initialBitrateCapKbps: Int?) {
        firstFrameEmitted = false
        let item = AVPlayerItem(url: hlsUrl)
        if let cap = initialBitrateCapKbps { item.preferredPeakBitRate = Double(cap * 1000) }
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        player.replaceCurrentItem(with: item)
        wireObservers(for: item)
        startTs = CFAbsoluteTimeGetCurrent()
        onEvent?("prepared", ["url": hlsUrl.absoluteString])
        eventBus.enqueue(.init(name: "prepared", props: ["url": .init(hlsUrl.absoluteString)]))
        if let v = attachedView { attach(to: v) }
    }
    
    public func play() { player.play(); onEvent?("playback_start", [:]); eventBus.enqueue(.init(name: "playback_start")) }
    public func pause() { player.pause(); onEvent?("paused", [:]); eventBus.enqueue(.init(name: "paused")) }
    public func seek(ms: Int64) {
        player.seek(to: CMTime(value: ms, timescale: 1000)) { [weak self] _ in
            self?.onEvent?("seek_complete", ["ms": ms])
            self?.eventBus.enqueue(.init(name: "seek_complete", props: ["ms": .init(ms)]))
        }
    }
    public func dispose() {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        itemObs = nil; rateObs = nil; player.replaceCurrentItem(with: nil); onEvent?("disposed", [:])
    }
    
    public func attach(to view: UIView) {
        attachedView = view
        if playerLayer == nil {
            playerLayer = AVPlayerLayer(player: player); playerLayer?.videoGravity = .resizeAspectFill; view.layer.addSublayer(playerLayer!)
        } else {
            playerLayer?.player = player
            if playerLayer?.superlayer !== view.layer { playerLayer?.removeFromSuperlayer(); view.layer.addSublayer(playerLayer!) }
        }
        playerLayer?.frame = view.bounds; playerLayer?.needsDisplayOnBoundsChange = true; view.layer.setNeedsLayout()
    }
    
    public var positionSeconds: Double { CMTimeGetSeconds(player.currentTime()) }
    public var durationSeconds: Double { if let d = player.currentItem?.duration, d.isNumeric { return CMTimeGetSeconds(d) }; return 0 }
    
    private func wireObservers(for item: AVPlayerItem) {
        itemObs = item.observe(\.status, options: [.new, .initial]) { [weak self] itm, _ in
            guard let self = self else { return }
            if itm.status == .readyToPlay && !self.firstFrameEmitted {
                self.firstFrameEmitted = true
                let tffMs = Int((CFAbsoluteTimeGetCurrent() - self.startTs) * 1000)
                self.onEvent?("first_frame", ["ms": tffMs]); self.eventBus.enqueue(.init(name: "first_frame", props: ["ms": .init(tffMs)]))
            } else if itm.status == .failed {
                self.onEvent?("error", ["message": itm.error?.localizedDescription ?? "unknown"])
                self.eventBus.enqueue(.init(name: "error", props: ["message": .init(itm.error?.localizedDescription ?? "unknown")]))
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleStall), name: .AVPlayerItemPlaybackStalled, object: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 2, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(t)
            self.eventBus.enqueue(.init(name: "playback_progress", props: ["position_s": .init(seconds)]))
        }
    }
    
    @objc private func handleStall() {
        onEvent?("rebuffer_start", [:]); eventBus.enqueue(.init(name: "rebuffer_start"))
        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            guard let self = self else { return }
            if self.player.timeControlStatus == .playing {
                self.onEvent?("rebuffer_end", [:]); self.eventBus.enqueue(.init(name: "rebuffer_end")); self.rateObs = nil
            }
        }
    }
}

public final class PlayerPool {
    private var pool: [AVPlayerKit] = []
    private let eventBus: EventBus
    private let maxSize: Int
    public init(size: Int = 3, eventBus: EventBus) {
        self.maxSize = max(2, size); self.eventBus = eventBus
        for _ in 0..<self.maxSize { pool.append(AVPlayerKit(eventBus: eventBus)) }
    }
    public func acquire() -> AVPlayerKit { return pool.removeFirst() }
    public func release(_ player: AVPlayerKit) { pool.append(player) }
    public func preloadNext(_ url: URL) {
        guard let p = pool.first else { return }
        p.prepare(hlsUrl: url, initialBitrateCapKbps: 700)
        eventBus.enqueue(.init(name: "preload_started", props: ["url": .init(url.absoluteString)]))
    }
}
