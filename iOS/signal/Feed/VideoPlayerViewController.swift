//
//  VideoPlayerViewController.swift
//  signal
//
//  Individual video player view controller with gesture handling
//

import UIKit
import AVFoundation

class VideoPlayerViewController: UIViewController {
    
    // MARK: - Properties
    private let videoItem: VideoItem
    private var manifest: MediaManifest?
    private var player: PlayerKit?
    private let playerView = UIView()
    private let scrubPreviewView: ScrubPreviewView
    private let storyboardProvider = StoryboardProvider()
    private let errorOverlay = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    
    weak var delegate: VideoPlayerDelegate?
    
    private var isLongPressing = false
    private var scrubStartTime: TimeInterval = 0
    private var lastScrubTargetTime: TimeInterval = 0
    private var longPressTimer: Timer?
    // (seek slider removed)
    private let scrubFeatureEnabled: Bool = {
        let env = ProcessInfo.processInfo.environment["ENABLE_LONG_PRESS_SCRUB"]?.lowercased() ?? "0"
        return env == "1" || env == "true" || env == "yes"
    }()
    private enum ScrubState { case idle, scrubbingWasPlaying, scrubbingWasPaused }
    private var scrubState: ScrubState = .idle
    private var tapGesture: UITapGestureRecognizer?
    private var longPressGesture: UILongPressGestureRecognizer?
    private var didWirePagePan: Bool = false
    
    // MARK: - Initialization
    private let sharedEventBus: EventBusProtocol?
    
    init(videoItem: VideoItem, eventBus: EventBusProtocol?) {
        self.videoItem = videoItem
        self.sharedEventBus = eventBus
        self.scrubPreviewView = ScrubPreviewView(provider: storyboardProvider)
        super.init(nibName: nil, bundle: nil)
    }

    // Expose identity for paging reuse
    var videoId: String { videoItem.videoId }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        loadManifest()
    }

    // (no extra autoplay in viewDidAppear; autoplay is gated in PlayerKit when attached & ready)
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Set accessibility labels
        view.accessibilityLabel = "Video player"
        view.accessibilityHint = "Tap to play or pause, long press to scrub through video"
        // Activate audio for visible playback scope
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
        // Ensure audio session releases promptly when leaving this view
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didWirePagePan {
            wireRequireToFailWithPagePanIfAvailable()
            didWirePagePan = true
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Player view
        playerView.backgroundColor = .black
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)
        
        // Scrub preview (initially hidden)
        scrubPreviewView.isHidden = true
        scrubPreviewView.isUserInteractionEnabled = false
        scrubPreviewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubPreviewView)
        
        // Error overlay (initially hidden)
        setupErrorOverlay()

        // (seek slider removed)
        
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            scrubPreviewView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrubPreviewView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            scrubPreviewView.widthAnchor.constraint(equalToConstant: 160),
            scrubPreviewView.heightAnchor.constraint(equalToConstant: 120)
        ])

        // (seek slider constraints removed)
    }
    
    private func setupErrorOverlay() {
        errorOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        errorOverlay.isHidden = true
        errorOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorOverlay)
        
        errorLabel.text = "Failed to load video"
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorOverlay.addSubview(errorLabel)
        
        retryButton.setTitle("Tap to Retry", for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        retryButton.backgroundColor = .systemBlue
        retryButton.layer.cornerRadius = 8
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        errorOverlay.addSubview(retryButton)
        
        NSLayoutConstraint.activate([
            errorOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: errorOverlay.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorOverlay.centerYAnchor, constant: -20),
            
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 20),
            retryButton.centerXAnchor.constraint(equalTo: errorOverlay.centerXAnchor),
            retryButton.widthAnchor.constraint(equalToConstant: 140),
            retryButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Seek slider constraints are set in setupUI after the slider is added
    }
    
    private func setupGestures() {
        // Tap gesture for play/pause — attach to playerView only
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        // no delegate; keep minimal footprint
        playerView.addGestureRecognizer(tap)
        self.tapGesture = tap

        // Long press gesture for scrubbing (feature-flagged)
        if scrubFeatureEnabled {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            lp.minimumPressDuration = 0.3
            lp.cancelsTouchesInView = false
            // no delegate; keep minimal footprint
            playerView.addGestureRecognizer(lp)
            self.longPressGesture = lp
        }
        // (page pan coordination is wired in viewDidAppear when parent is present)
    }

    // Wire child gestures to fail if the page's pan recognizes (both official API and scroll view fallback)
    private func wireRequireToFailWithPagePanIfAvailable() {
        // Find parent UIPageViewController
        var node: UIViewController? = self
        var pageVC: UIPageViewController?
        while let p = node?.parent {
            if let pvc = p as? UIPageViewController { pageVC = pvc; break }
            node = p
        }
        guard let pvc = pageVC else { return }
        var pagePanCount = 0
        for gr in pvc.gestureRecognizers {
            if let pan = gr as? UIPanGestureRecognizer {
                tapGesture?.require(toFail: pan)
                longPressGesture?.require(toFail: pan)
                pagePanCount += 1
            }
        }
        // Fallback to internal scroll view pan if needed
        var scrollPanCount = 0
        if pagePanCount == 0 {
            if let scrollView = pvc.view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                let pan = scrollView.panGestureRecognizer
                tapGesture?.require(toFail: pan)
                longPressGesture?.require(toFail: pan)
                scrollPanCount = 1
            }
        }
        print("[PageVC] wired child gestures to fail for pagePans=\(pagePanCount) scrollPans=\(scrollPanCount)")
    }
    
    
    // MARK: - Manifest Loading
    private func loadManifest() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: videoItem.mediaManifestUrl)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                manifest = try decoder.decode(MediaManifest.self, from: data)
                
                await MainActor.run {
                    setupPlayer()
                    loadStoryboard()
                }
            } catch {
                print("[VideoPlayer] Failed to load manifest: \(error)")
                showError()
            }
        }
    }
    
    private func loadStoryboard() {
        guard let vttUrl = manifest?.thumbnailVttUrl else { return }
        Task {
            await storyboardProvider.loadVTT(from: vttUrl)
        }
    }
    
    // MARK: - Player Setup
    private func setupPlayer() {
        guard let manifest = manifest else { return }
        
        // For now, create a player and attach the shared EventBus
        player = PlayerKit()
        if let eb = sharedEventBus {
            player?.setEventBus(eb)
        } else {
            player?.setEventBus(EventBus(endpoint: URL(string: ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.example.com")!.appendingPathComponent("/v1/events")))
        }
        player?.prepare(
            hlsUrl: manifest.hlsUrl,
            videoId: manifest.videoId,
            initialBitrateCapKbps: 700
        )
        player?.attach(to: playerView)
    }
    
    // MARK: - Playback Control
    func play() {
        player?.play()
        errorOverlay.isHidden = true
    }
    
    func pause() {
        player?.pause()
    }
    
    func togglePlayPause() {
        player?.togglePlayPause()
        // (no seek visibility updates)
    }

    var isPlayingNow: Bool { player?.isCurrentlyPlaying ?? false }
    
    // MARK: - Gesture Handlers
    @objc private func handleTap() {
        delegate?.videoPlayerDidTap(self)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard scrubFeatureEnabled else { return }
        let location = gesture.location(in: view)
        handleLongPress(state: gesture.state, location: location)
    }
    
    func handleLongPress(state: UIGestureRecognizer.State, location: CGPoint) {
        switch state {
        case .began:
            startScrubbing(at: location)
        case .changed:
            updateScrubbing(at: location)
        case .ended, .cancelled:
            endScrubbing()
        default:
            break
        }
    }
    
    private func startScrubbing(at location: CGPoint) {
        guard scrubFeatureEnabled else { return }
        isLongPressing = true
        scrubStartTime = player?.currentTime ?? 0
        lastScrubTargetTime = scrubStartTime
        scrubState = (player?.isCurrentlyPlaying ?? false) ? .scrubbingWasPlaying : .scrubbingWasPaused
        player?.startScrubbing()
        // (no seek bar)
        
        scrubPreviewView.isHidden = false
        scrubPreviewView.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.scrubPreviewView.alpha = 1
        }
        
        updateScrubbing(at: location)
    }
    
    private func updateScrubbing(at location: CGPoint) {
        guard isLongPressing, let duration = player?.duration else { return }
        
        // Calculate scrub position based on horizontal position
        let progress = location.x / view.bounds.width
        let clamped = max(0.0, min(1.0, Double(progress)))
        let targetTime = duration * clamped
        lastScrubTargetTime = targetTime
        
        // Update preview with throttling
        scrubPreviewView.updatePreview(at: targetTime)
    }
    
    private func endScrubbing() {
        guard scrubFeatureEnabled else { return }
        guard isLongPressing else { return }
        isLongPressing = false

        // Seek to the last computed scrub target time
        player?.endScrubbing(at: lastScrubTargetTime)

        UIView.animate(withDuration: 0.2) {
            self.scrubPreviewView.alpha = 0
        } completion: { _ in
            self.scrubPreviewView.isHidden = true
        }
        // Resume only if we were playing before
        if case .scrubbingWasPlaying = scrubState {
            player?.play()
        }
        scrubState = .idle
    }

    // (seek slider-related actions removed)
    
    // MARK: - Error Handling
    private func showError() {
        errorOverlay.isHidden = false
    }
    
    @objc private func retryTapped() {
        errorOverlay.isHidden = true
        loadManifest()
    }
}
