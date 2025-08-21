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
    private var longPressTimer: Timer?
    
    // MARK: - Initialization
    init(videoItem: VideoItem) {
        self.videoItem = videoItem
        self.scrubPreviewView = ScrubPreviewView(provider: storyboardProvider)
        super.init(nibName: nil, bundle: nil)
    }
    
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Set accessibility labels
        view.accessibilityLabel = "Video player"
        view.accessibilityHint = "Tap to play or pause, long press to scrub through video"
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
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
        scrubPreviewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubPreviewView)
        
        // Error overlay (initially hidden)
        setupErrorOverlay()
        
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
    }
    
    private func setupGestures() {
        // Tap gesture for play/pause
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
        
        // Long press gesture for scrubbing
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3
        view.addGestureRecognizer(longPressGesture)
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
        
        // Get player from pool or create new one
        // In a real implementation, this would come from the PlayerPool
        player = PlayerKit()
        player?.setEventBus(EventBus(endpoint: URL(string: ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.example.com/v1/events")!))
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
    }
    
    // MARK: - Gesture Handlers
    @objc private func handleTap() {
        delegate?.videoPlayerDidTap(self)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
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
        isLongPressing = true
        scrubStartTime = player?.currentTime ?? 0
        player?.startScrubbing()
        
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
        let targetTime = duration * Double(progress)
        
        // Update preview with throttling
        scrubPreviewView.updatePreview(at: targetTime)
    }
    
    private func endScrubbing() {
        guard isLongPressing else { return }
        isLongPressing = false
        
        // Get final scrub position
        if let duration = player?.duration {
            let progress = scrubPreviewView.center.x / view.bounds.width
            let targetTime = duration * Double(progress)
            player?.endScrubbing(at: targetTime)
        }
        
        UIView.animate(withDuration: 0.2) {
            self.scrubPreviewView.alpha = 0
        } completion: { _ in
            self.scrubPreviewView.isHidden = true
        }
    }
    
    // MARK: - Error Handling
    private func showError() {
        errorOverlay.isHidden = false
    }
    
    @objc private func retryTapped() {
        errorOverlay.isHidden = true
        loadManifest()
    }
}