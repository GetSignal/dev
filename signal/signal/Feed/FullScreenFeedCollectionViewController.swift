//
//  FullScreenFeedCollectionViewController.swift
//  signal
//
//  Vertically paged UICollectionView (one full-screen cell per item)
//  Industry-standard approach for TikTok-like feeds.
//

import UIKit

final class FullScreenFeedCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {

    // MARK: - Data
    private var items: [VideoItem] = []
    private var itemIds: [String] = []
    private let eventBus: EventBusProtocol
    private let playerPool: PlayerPool

    // MARK: - Init
    init(items: [VideoItem], eventBus: EventBusProtocol, playerPool: PlayerPool) {
        self.eventBus = eventBus
        self.playerPool = playerPool
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        super.init(collectionViewLayout: layout)
        self.items = items
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(FeedCell.self, forCellWithReuseIdentifier: FeedCell.reuseId)
    }

    // Ensure layout updates on rotation and keep single playback
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            // Snap to the nearest page to avoid two partially visible cells after rotation
            let index = self.currentPageIndex()
            if index >= 0 && index < self.items.count {
                self.collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: false)
            }
            self.enforceSinglePlayingVisibleCell()
        })
    }

    // MARK: - Public
    func updateItems(_ newItems: [VideoItem]) {
        let newIds = newItems.map { $0.videoId }
        guard newIds != itemIds else { return }
        self.items = newItems
        self.itemIds = newIds
        collectionView.reloadData()
    }

    // MARK: - Data Source
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
        cell.configure(item: items[indexPath.item], eventBus: eventBus)
        return cell
    }

    // MARK: - Delegate FlowLayout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }

    // MARK: - Display lifecycle (attach/detach players)
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? FeedCell else { return }
        let item = items[indexPath.item]
        // Simpler: each visible cell owns its PlayerKit; we pause/detach on end display
        let player = PlayerKit()
        cell.attach(player: player, with: item)
        // Visible-only autoplay handled by PlayerKit when attached & ready
    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? FeedCell, let player = cell.detachPlayerIfAny() else { return }
        player.pause()
    }

    // Enforce only one visible cell plays at a time
    private func enforceSinglePlayingVisibleCell() {
        let visibleIPs = collectionView.indexPathsForVisibleItems
        guard !visibleIPs.isEmpty else { return }
        // Choose the cell whose center is closest to the collection view's visible center
        let visibleCenterY = collectionView.contentOffset.y + collectionView.bounds.height / 2
        var bestIP: IndexPath?
        var smallestDelta: CGFloat = .greatestFiniteMagnitude
        for ip in visibleIPs {
            if let cell = collectionView.cellForItem(at: ip) {
                let delta = abs(cell.center.y - visibleCenterY)
                if delta < smallestDelta {
                    smallestDelta = delta
                    bestIP = ip
                }
            }
        }
        guard let primaryIP = bestIP, let primaryCell = collectionView.cellForItem(at: primaryIP) as? FeedCell else {
            // If we couldn't compute, pause all to avoid mixing
            for ip in visibleIPs { (collectionView.cellForItem(at: ip) as? FeedCell)?.pauseIfNeeded() }
            return
        }
        // Pause all others
        for ip in visibleIPs where ip != primaryIP {
            (collectionView.cellForItem(at: ip) as? FeedCell)?.pauseIfNeeded()
        }
        // Ensure primary plays
        primaryCell.playIfNeeded()
    }

    private func currentPageIndex() -> Int {
        guard collectionView.bounds.height > 0 else { return 0 }
        let offsetY = collectionView.contentOffset.y
        let page = Int(round(offsetY / collectionView.bounds.height))
        return max(0, min(items.count - 1, page))
    }

    // Ensure single playback after user finishes scrolling
    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        enforceSinglePlayingVisibleCell()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { enforceSinglePlayingVisibleCell() }
    }
}

// MARK: - Cell
final class FeedCell: UICollectionViewCell {
    static let reuseId = "FeedCell"

    private let videoContainer = UIView()
    private var tapRecognizer: UITapGestureRecognizer?
    private let seekSlider = UISlider()
    private let timeLabel = UILabel()
    private var player: PlayerKit?
    private var item: VideoItem?
    private var eventBus: EventBusProtocol?
    private var loadTask: Task<Void, Never>?
    private var uiTimer: Timer?
    private var durationSeconds: Double = 0
    private var isSeeking: Bool = false
    private var wasPlayingBeforeSeek: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(videoContainer)

        // Full-surface tap on video to toggle play/pause (non-greedy)
        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlayPause))
        tap.cancelsTouchesInView = false
        videoContainer.addGestureRecognizer(tap)
        tapRecognizer = tap

        // Seek slider + time label (visible when paused or interacting)
        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.isHidden = true
        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.addTarget(self, action: #selector(seekTouchDown), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(seekValueChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(seekTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        contentView.addSubview(seekSlider)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        timeLabel.isHidden = true
        contentView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            seekSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            seekSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            seekSlider.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.bottomAnchor.constraint(equalTo: seekSlider.topAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: VideoItem, eventBus: EventBusProtocol) {
        self.item = item
        self.eventBus = eventBus
    }

    func attach(player: PlayerKit, with item: VideoItem) {
        self.player = player
        player.attach(to: videoContainer)
        // Prepare visible item with autoplay=true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: item.mediaManifestUrl)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(MediaManifest.self, from: data)
                await MainActor.run {
                    self.durationSeconds = Double(manifest.durationMs) / 1000.0
                    player.prepare(hlsUrl: manifest.hlsUrl, videoId: manifest.videoId, initialBitrateCapKbps: 700, autoPlay: true)
                    player.attach(to: videoContainer)
                    // Ensure start if visible (covers edge cases where observer gating misses)
                    if self.window != nil { player.play() }
                    self.startUiTimer()
                }
            } catch {
                // simple fallback: leave cell idle
                print("[FeedCell] Failed to load manifest: \(error)")
            }
        }
    }

    func detachPlayerIfAny() -> PlayerKit? {
        loadTask?.cancel()
        loadTask = nil
        stopUiTimer()
        seekSlider.isHidden = true
        timeLabel.isHidden = true
        let p = player
        player = nil
        return p
    }

    @objc private func togglePlayPause() {
        guard let player = player else { return }
        player.togglePlayPause()
    }

    func pauseIfNeeded() { player?.pause() }
    func playIfNeeded() {
        // If already playing, do nothing; else start
        if player?.isCurrentlyPlaying == false { player?.play() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        stopUiTimer()
        seekSlider.isHidden = true
        timeLabel.isHidden = true
        player = nil
        item = nil
    }

    // MARK: - Seek controls
    @objc private func seekTouchDown() {
        guard let player = player else { return }
        wasPlayingBeforeSeek = player.isCurrentlyPlaying
        player.pause()
        isSeeking = true
        showSeekUi()
        eventBus?.trackPreviewScrubStart()
    }

    @objc private func seekValueChanged() {
        guard durationSeconds > 0 else { return }
        let target = Double(seekSlider.value) * durationSeconds
        timeLabel.text = formatTime(seconds: target)
    }

    @objc private func seekTouchUp() {
        guard let player = player, durationSeconds > 0 else { return }
        let target = Double(seekSlider.value) * durationSeconds
        player.seek(to: target)
        eventBus?.trackPreviewScrubCommit(seconds: target)
        if wasPlayingBeforeSeek { player.play() } else { showSeekUi() }
        isSeeking = false
        if wasPlayingBeforeSeek { hideSeekUi() }
    }

    private func showSeekUi() {
        seekSlider.isHidden = false
        timeLabel.isHidden = false
    }

    private func hideSeekUi() {
        seekSlider.isHidden = true
        timeLabel.isHidden = true
    }

    private func startUiTimer() {
        stopUiTimer()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player, self.durationSeconds > 0 else { return }
            if !self.isSeeking {
                let pos = player.currentTime
                let fraction = max(0.0, min(1.0, pos / self.durationSeconds))
                self.seekSlider.value = Float(fraction)
                self.timeLabel.text = self.formatTime(seconds: pos)
                // Show slider only when paused
                if player.isCurrentlyPlaying { self.hideSeekUi() }
            }
        }
    }

    private func stopUiTimer() { uiTimer?.invalidate(); uiTimer = nil }

    private func formatTime(seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
