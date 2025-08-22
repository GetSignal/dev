// FeedViewController.swift
// Signal Video — Feed Controller (iOS)
// Created: 2025-08-15

import UIKit

struct VideoItem { let id: String; let hlsUrl: URL; let durationMs: Int64? }

final class FeedViewController: UIViewController {
    private let videoView = UIView()
    private let eventBus = HttpEventBus(endpoint: URL(string: "https://api.example.com/event")!)
    private lazy var pool = PlayerPool(size: 3, eventBus: eventBus)
    private var items: [VideoItem] = []
    private var currentIndex: Int = 0
    private var current: AVPlayerKit?
    private var viewStart: CFAbsoluteTime = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        videoView.frame = view.bounds; videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(videoView)
        
        let up = UISwipeGestureRecognizer(target: self, action: #selector(nextClip)); up.direction = .up; view.addGestureRecognizer(up)
        let down = UISwipeGestureRecognizer(target: self, action: #selector(prevClip)); down.direction = .down; view.addGestureRecognizer(down)
        
        items = [
            VideoItem(id: "a1", hlsUrl: URL(string: "https://cdn.example.com/vod/a1/master.m3u8")!, durationMs: nil),
            VideoItem(id: "b2", hlsUrl: URL(string: "https://cdn.example.com/vod/b2/master.m3u8")!, durationMs: nil),
            VideoItem(id: "c3", hlsUrl: URL(string: "https://cdn.example.com/vod/c3/master.m3u8")!, durationMs: nil)
        ]
        startAt(index: 0)
    }
    
    private func startAt(index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        let item = items[index]
        current = pool.acquire()
        current?.attach(to: videoView)
        current?.onEvent = { [weak self] name, props in self?.handleEvent(name, props) }
        current?.prepare(hlsUrl: item.hlsUrl, initialBitrateCapKbps: 700)
        current?.play()
        viewStart = CFAbsoluteTimeGetCurrent()
        if let next = nextIndex() { pool.preloadNext(items[next].hlsUrl) }
    }
    
    @objc private func nextClip() {
        guard let c = current, let next = nextIndex() else { return }
        emitViewEnd(for: items[currentIndex], using: c)
        pool.release(c)
        currentIndex = next
        current = pool.acquire()
        current?.attach(to: videoView)
        current?.onEvent = { [weak self] name, props in self?.handleEvent(name, props) }
        current?.play()
        viewStart = CFAbsoluteTimeGetCurrent()
        if let n = nextIndex() { pool.preloadNext(items[n].hlsUrl) }
    }
    
    @objc private func prevClip() {
        guard let c = current else { return }
        emitViewEnd(for: items[currentIndex], using: c)
        pool.release(c)
        currentIndex = max(0, currentIndex - 1)
        startAt(index: currentIndex)
    }
    
    private func nextIndex() -> Int? { let ni = currentIndex + 1; return items.indices.contains(ni) ? ni : nil }
    
    private func emitViewEnd(for item: VideoItem, using player: AVPlayerKit) {
        let dwellMs = Int((CFAbsoluteTimeGetCurrent() - viewStart) * 1000)
        let pos = player.positionSeconds
        let dur = max(player.durationSeconds, 0.1)
        let pct = Int((pos / dur) * 100.0)
        eventBus.enqueue(TelemetryEvent(name: "view_end", props: ["video_id": AnyCodable(item.id), "dwell_ms": AnyCodable(dwellMs), "percent_complete": AnyCodable(pct)]))
        eventBus.flushNow()
    }
    
    private func handleEvent(_ name: String, _ props: [String: Any]) { /* analytics hook */ }
}
