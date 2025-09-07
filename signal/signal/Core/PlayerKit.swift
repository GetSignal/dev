//
//  PlayerKit.swift
//  signal
//
//  AVPlayer wrapper with autoplay, bitrate control, and telemetry
//

import Foundation
import AVFoundation
import AVKit
import UIKit
import Combine

class PlayerKit: NSObject {
    
    // MARK: - Properties
    private var player: AVPlayer
    private var playerLayer: AVPlayerLayer?
    private var playerItem: AVPlayerItem?
    private var eventBus: EventBusProtocol?
    
    private var videoId: String?
    private var initialBitrateCapKbps: Int = 700 // Default cap as per spec
    private var hasAppliedInitialBitrateCap = false
    private var shouldAutoPlay: Bool = true
    private var playbackStartTime: Date?
    private var isPlaying = false
    private var wasPlayingBeforeScrub = false
    private var isAttachedToView = false
    
    // Observers
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var stallObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var errorObserver: NSKeyValueObservation?
    
    // Metrics
    private var ttffStartTime: Date?
    private var hasReportedTTFF = false
    private var rebufferCount = 0
    private var rebufferTotalMs = 0
    private var lastStallTime: Date?
    private var loopCount = 0
    
    // MARK: - Initialization
    override init() {
        self.player = AVPlayer()
        super.init()
        setupPlayer()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupPlayer() {
        player.automaticallyWaitsToMinimizeStalling = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        
        // Configure audio session category; activation handled by controller lifecycle
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }
    
    // MARK: - Public Interface
    func prepare(hlsUrl: URL, videoId: String, initialBitrateCapKbps: Int = 700, autoPlay: Bool = true) {
        cleanup()
        
        self.videoId = videoId
        self.initialBitrateCapKbps = initialBitrateCapKbps
        self.shouldAutoPlay = autoPlay
        self.hasAppliedInitialBitrateCap = false
        self.ttffStartTime = Date()
        self.hasReportedTTFF = false
        self.loopCount = 0
        
        let asset = AVURLAsset(url: hlsUrl)
        playerItem = AVPlayerItem(asset: asset)
        
        // Apply initial bitrate cap
        applyBitrateCap(initialBitrateCapKbps)
        
        setupObservers()
        player.replaceCurrentItem(with: playerItem)
    }

    // Backward-compatible overload (keeps existing call sites working)
    func prepare(hlsUrl: URL, videoId: String, initialBitrateCapKbps: Int = 700) {
        prepare(hlsUrl: hlsUrl, videoId: videoId, initialBitrateCapKbps: initialBitrateCapKbps, autoPlay: true)
    }
    
    func play() {
        if playbackStartTime == nil {
            playbackStartTime = Date()
            eventBus?.trackViewStart(videoId: videoId ?? "unknown")
        }
        isPlaying = true
        player.play()
    }
    
    func pause() {
        // User-initiated pause should never auto-resume
        shouldAutoPlay = false
        isPlaying = false
        player.pause()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
        eventBus?.trackTapPlayPause(playing: isPlaying)
    }
    
    func seek(to seconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            completion?(finished)
            if finished && self?.wasPlayingBeforeScrub == true {
                self?.play()
            }
        }
    }
    
    func startScrubbing() {
        wasPlayingBeforeScrub = isPlaying
        pause()
        eventBus?.trackPreviewScrubStart()
    }
    
    func endScrubbing(at seconds: TimeInterval) {
        eventBus?.trackPreviewScrubCommit(seconds: seconds)
        seek(to: seconds) { [weak self] _ in
            if self?.wasPlayingBeforeScrub == true {
                self?.play()
            }
        }
    }
    
    func attach(to view: UIView) {
        playerLayer?.removeFromSuperlayer()
        
        let newLayer = AVPlayerLayer(player: player)
        newLayer.frame = view.bounds
        newLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(newLayer)
        
        playerLayer = newLayer
        isAttachedToView = true
        // If item already ready and autoplay allowed, start now
        if shouldAutoPlay, let status = playerItem?.status, status == .readyToPlay {
            DispatchQueue.main.async { [weak self] in self?.play() }
        }
    }
    
    func detach() {
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        isAttachedToView = false
    }
    
    func prefetch(_ seconds: TimeInterval) {
        // Prefetch implementation - buffer ahead
        guard let item = playerItem else { return }
        item.preferredForwardBufferDuration = seconds
    }
    
    // MARK: - Properties Access
    var currentTime: TimeInterval {
        return player.currentTime().seconds
    }
    
    var duration: TimeInterval? {
        guard let item = playerItem else { return nil }
        let duration = item.duration.seconds
        return duration.isFinite ? duration : nil
    }
    
    var percentComplete: Int {
        guard let duration = duration, duration > 0 else { return 0 }
        return Int((currentTime / duration) * 100)
    }
    
    // MARK: - Cleanup
    func cleanup() {
        // Report view end if needed
        if let videoId = videoId, let startTime = playbackStartTime {
            let dwellMs = Int(Date().timeIntervalSince(startTime) * 1000)
            eventBus?.trackViewEnd(videoId: videoId, dwellMs: dwellMs, percentComplete: percentComplete)
        }
        
        // Remove observers
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        stallObserver?.invalidate()
        bufferObserver?.invalidate()
        errorObserver?.invalidate()
        
        // Reset state
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        videoId = nil
        playbackStartTime = nil
        isPlaying = false
        hasReportedTTFF = false
        rebufferCount = 0
        rebufferTotalMs = 0
    }
    
    // MARK: - Private Methods
    private func applyBitrateCap(_ kbps: Int) {
        guard let item = playerItem else { return }
        
        // Apply bitrate cap in bits per second
        item.preferredPeakBitRate = Double(kbps * 1000)
        hasAppliedInitialBitrateCap = true
        
        // Remove cap after initial playback stabilizes (e.g., after 3 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.hasAppliedInitialBitrateCap else { return }
            self.playerItem?.preferredPeakBitRate = 0 // Remove cap
            self.hasAppliedInitialBitrateCap = false
        }
    }
    
    private func setupObservers() {
        guard let item = playerItem else { return }
        
        // Status observer
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                if !self.hasReportedTTFF { self.reportTTFF() }
                if self.shouldAutoPlay && self.isAttachedToView {
                    DispatchQueue.main.async { [weak self] in self?.play() }
                }
            } else if item.status == .failed {
                self.handleError(item.error)
            }
        }
        
        // Rate observer (for stalls)
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            if player.rate == 0 && self?.isPlaying == true {
                self?.handleStall()
            } else if player.rate > 0 && self?.lastStallTime != nil {
                self?.handleStallRecovered()
            }
        }
        
        // Buffer observer
        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp) { [weak self] item, _ in
            if !item.isPlaybackLikelyToKeepUp && self?.isPlaying == true {
                self?.handleStall()
            }
        }
        
        // Error observer
        errorObserver = item.observe(\.error) { [weak self] item, _ in
            if let error = item.error {
                self?.handleError(error)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnded), name: .AVPlayerItemDidPlayToEndTime, object: item)
        
        // Periodic time observer for bitrate tracking
        let interval = CMTime(seconds: 5, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.reportCurrentBitrate()
        }
    }
    
    private func reportTTFF() {
        guard !hasReportedTTFF, let startTime = ttffStartTime else { return }
        let ttffMs = Int(Date().timeIntervalSince(startTime) * 1000)
        eventBus?.trackTimeToFirstFrame(ms: ttffMs)
        hasReportedTTFF = true
    }
    
    private func handleStall() {
        guard lastStallTime == nil else { return }
        lastStallTime = Date()
        rebufferCount += 1
    }
    
    private func handleStallRecovered() {
        guard let stallTime = lastStallTime else { return }
        let stallDuration = Int(Date().timeIntervalSince(stallTime) * 1000)
        rebufferTotalMs += stallDuration
        lastStallTime = nil
        
        eventBus?.trackRebuffer(count: rebufferCount, totalMs: rebufferTotalMs)
    }
    
    private func reportCurrentBitrate() {
        guard let item = playerItem,
              let accessLog = item.accessLog(),
              let lastEvent = accessLog.events.last else { return }
        
        let bitrateKbps = Int(lastEvent.indicatedBitrate / 1000)
        if bitrateKbps > 0 {
            eventBus?.trackSelectedBitrate(kbps: bitrateKbps)
        }
    }
    
    private func handleError(_ error: Error?) {
        guard let error = error, let videoId = videoId else { return }
        let errorCode = (error as NSError).code
        eventBus?.trackPlaybackError(videoId: videoId, code: "E_HLS_\(errorCode)")
    }

    @objc private func handleEnded() {
        guard let videoId = videoId else { return }
        loopCount += 1
        eventBus?.trackPlaybackLoop(videoId: videoId, loopCount: loopCount)
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            if self.isAttachedToView {
                self.play()
            }
        }
    }
    
    // MARK: - Event Bus
    func setEventBus(_ eventBus: EventBusProtocol) {
        self.eventBus = eventBus
    }

    // MARK: - State Exposure
    var isCurrentlyPlaying: Bool { isPlaying }

    // (Removed previewSeek helper to revert to prior behavior)
}
