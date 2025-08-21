// SwiftUIFeedView.swift
// Production-ready feed: vertical paging + PlayerPool
// - Audio ON by default (AVAudioSession.playback)
// - Tap-to-play/pause
// - Long-press scrub with WebVTT storyboard thumbnails (LRU + neighbor prefetch)
// - Snap scrolling tuned (no bounce, fast decel)
// - Lifecycle safe: background/foreground + audio interruptions
// - Error overlay with tap-to-retry
// - Telemetry flush debounced
// - Accessibility labels
//
// Assumes PlayerKit-iOS.swift defines: AVPlayerKit { attach, prepare(hlsUrl:...), play(), pause(), seek(ms:), positionSeconds, durationSeconds, onEvent }
// Assumes EventBus { enqueue(TelemetryEvent), flushNow() }

import SwiftUI
import UIKit
import AVFoundation

// MARK: - Helpers

final class Debouncer {
    private let interval: TimeInterval
    private var work: DispatchWorkItem?
    init(_ interval: TimeInterval) { self.interval = interval }
    func call(_ block: @escaping () -> Void) {
        work?.cancel()
        let w = DispatchWorkItem(block: block)
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: w)
    }
}

// MARK: - Models

public struct VideoItem: Identifiable, Equatable {
    public let id: String
    public let hlsUrl: URL
    /// Absolute URL to versioned storyboard VTT (e.g. .../v7/storyboard.vtt)
    public let thumbnailHint: String?
    public init(id: String, hlsUrl: URL, thumbnailHint: String? = nil) {
        self.id = id; self.hlsUrl = hlsUrl; self.thumbnailHint = thumbnailHint
    }
}

// MARK: - Thumbnail provider protocol

public protocol ThumbnailProvider {
    func thumbnail(for item: VideoItem, at seconds: Double, completion: @escaping (UIImage?) -> Void)
}

// Default provider: WebVTT storyboard + sprite crop (LRU + neighbor prefetch)
public final class VTTStoryboardProvider: ThumbnailProvider {
    private struct Cue { let start: Double; let end: Double; let imageURL: URL; let rect: CGRect }
    private let queue = DispatchQueue(label: "signal.vtt.provider", qos: .userInitiated)
    private let imageCache = NSCache<NSURL, UIImage>()
    private var cueCache: [String: [Cue]] = [:]

    public init(maxImages: Int = 24) {
        imageCache.countLimit = maxImages
        // Large HTTP cache so CDN Cache-Control is honored
        if URLCache.shared.diskCapacity < 256 * 1024 * 1024 {
            URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                       diskCapacity: 256 * 1024 * 1024,
                                       diskPath: "signal-storyboard-http-cache")
        }
    }

    public func thumbnail(for item: VideoItem, at seconds: Double, completion: @escaping (UIImage?) -> Void) {
        guard let vtt = item.thumbnailHint, let vttURL = URL(string: vtt) else {
            completion(nil); return // no fallback here to avoid CPU spikes
        }
        queue.async {
            let cues = self.cues(for: vttURL)
            guard !cues.isEmpty else { DispatchQueue.main.async { completion(nil) }; return }
            let idx = cues.firstIndex { seconds >= $0.start && seconds < $0.end } ?? (seconds >= cues.last!.end ? cues.indices.last! : 0)
            let cue = cues[idx]
            if idx > 0 { self.prefetchSprite(cues[idx - 1].imageURL) }
            if idx + 1 < cues.count { self.prefetchSprite(cues[idx + 1].imageURL) }

            if let sprite = self.imageCache.object(forKey: cue.imageURL as NSURL) {
                let cropped = self.crop(sprite, rect: cue.rect)
                DispatchQueue.main.async { completion(cropped) }
            } else {
                var req = URLRequest(url: cue.imageURL)
                req.cachePolicy = .returnCacheDataElseLoad
                req.timeoutInterval = 6
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    guard let d = data, let img = UIImage(data: d) else { DispatchQueue.main.async { completion(nil) }; return }
                    self.imageCache.setObject(img, forKey: cue.imageURL as NSURL)
                    let cropped = self.crop(img, rect: cue.rect)
                    DispatchQueue.main.async { completion(cropped) }
                }.resume()
            }
        }
    }

    private func cues(for url: URL) -> [Cue] {
        if let c = cueCache[url.absoluteString] { return c }
        var text: String?
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url)
        req.cachePolicy = .returnCacheDataElseLoad
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let d = data { text = String(data: d, encoding: .utf8) }
            sem.signal()
        }.resume()
        sem.wait()
        let parsed = text.map(parseVTT(text:)) ?? []
        cueCache[url.absoluteString] = parsed
        return parsed
    }

    private func parseVTT(text: String) -> [Cue] {
        var out: [Cue] = []; var t0: Double?; var t1: Double?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("WEBVTT") { continue }
            if line.contains("-->") {
                let p = line.components(separatedBy: "-->")
                t0 = hmsToSec(p[0].trimmingCharacters(in: .whitespaces))
                t1 = hmsToSec(p[1].trimmingCharacters(in: .whitespaces))
            } else if line.contains("#xywh"), let s = t0, let e = t1 {
                let parts = line.components(separatedBy: "#xywh=")
                guard parts.count == 2, let base = URL(string: parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
                let nums = parts[1].split(separator: ",").compactMap { Double($0) }
                guard nums.count == 4 else { continue }
                out.append(Cue(start: s, end: e, imageURL: base, rect: CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])))
                t0 = nil; t1 = nil
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    private func prefetchSprite(_ url: URL) {
        if imageCache.object(forKey: url as NSURL) != nil { return }
        var req = URLRequest(url: url); req.cachePolicy = .returnCacheDataElseLoad
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let d = data, let img = UIImage(data: d) { self.imageCache.setObject(img, forKey: url as NSURL) }
        }.resume()
    }

    private func crop(_ image: UIImage, rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    private func hmsToSec(_ t: String) -> Double {
        let p = t.split(separator: ":").map(String.init)
        func sec(_ s: String) -> (Double, Double) {
            let a = s.split(separator: ".").map(String.init)
            return (Double(a[0]) ?? 0, a.count == 2 ? Double("0.\(a[1])") ?? 0 : 0)
        }
        if p.count == 2 { let (s, ms) = sec(p[1]); return (Double(p[0]) ?? 0) * 60 + s + ms }
        let (s, ms) = sec(p[2]); return (Double(p[0]) ?? 0) * 3600 + (Double(p[1]) ?? 0) * 60 + s + ms
    }
}

// MARK: - SwiftUI entry

public struct FeedView: View {
    private let items: [VideoItem]
    private let eventBus: EventBus
    private let thumbProvider: ThumbnailProvider

    public init(items: [VideoItem], eventBus: EventBus, thumbnailProvider: ThumbnailProvider? = nil) {
        self.items = items
        self.eventBus = eventBus
        self.thumbProvider = thumbnailProvider ?? VTTStoryboardProvider()
    }
    public var body: some View {
        Group {
            if items.isEmpty {
                Text("No videos").foregroundColor(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            } else {
                VideoPageView(items: items, eventBus: eventBus, thumbnailProvider: thumbProvider)
            }
        }.ignoresSafeArea()
    }
}

// MARK: - UIViewControllerRepresentable

struct VideoPageView: UIViewControllerRepresentable {
    let items: [VideoItem]
    let eventBus: EventBus
    let thumbnailProvider: ThumbnailProvider

    func makeUIViewController(context: Context) -> PageVC {
        let vc = PageVC(items: items, eventBus: eventBus, thumbnailProvider: thumbnailProvider)
        return vc
    }
    func updateUIViewController(_ uiViewController: PageVC, context: Context) {}
}

// MARK: - PageVC

final class PageVC: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let items: [VideoItem]
    private let eventBus: EventBus
    private let pool: PlayerPool
    private let thumbProvider: ThumbnailProvider
    private var currentIndex = 0
    private var viewStart: CFAbsoluteTime = 0
    private let flushDebouncer = Debouncer(0.2)
    private var wasPlayingBeforeBackground = false

    init(items: [VideoItem], eventBus: EventBus, thumbnailProvider: ThumbnailProvider) {
        self.items = items
        self.eventBus = eventBus
        self.thumbProvider = thumbnailProvider
        self.pool = PlayerPool(size: 3, eventBus: eventBus)
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
        self.dataSource = self
        self.delegate = self

        if let scroll = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scroll.bounces = false
            scroll.decelerationRate = .fast
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        registerForLifecycle()

        let first = makeContentVC(index: 0)
        setViewControllers([first], direction: .forward, animated: false, completion: nil)
        first.attachAndPlay()
        viewStart = CFAbsoluteTimeGetCurrent()
        if items.count > 1 { pool.preloadNext(items[1].hlsUrl) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func registerForLifecycle() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    }

    @objc private func appWillResignActive() {
        if let vc = viewControllers?.first as? VideoContentVC {
            wasPlayingBeforeBackground = vc.isPlaying
            vc.pause()
        }
    }
    @objc private func appDidBecomeActive() {
        if wasPlayingBeforeBackground, let vc = viewControllers?.first as? VideoContentVC {
            vc.play()
        }
    }
    @objc private func audioInterrupted(_ n: Notification) {
        guard let userInfo = n.userInfo,
              let typeVal = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
        if type == .began {
            (viewControllers?.first as? VideoContentVC)?.pause()
        } else if type == .ended {
            if let optVal = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) {
                (viewControllers?.first as? VideoContentVC)?.play()
            }
        }
    }

    private func makeContentVC(index: Int) -> VideoContentVC {
        let item = items[index]; let pk = pool.acquire()
        return VideoContentVC(index: index, item: item, playerKit: pk, pool: pool, eventBus: eventBus, thumbnailProvider: thumbProvider, flushDebouncer: flushDebouncer)
    }

    // DataSource
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let c = viewController as? VideoContentVC else { return nil }
        let prev = c.index - 1; return prev >= 0 ? makeContentVC(index: prev) : nil
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let c = viewController as? VideoContentVC else { return nil }
        let next = c.index + 1; return next < items.count ? makeContentVC(index: next) : nil
    }

    // Delegate
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let visible = viewControllers?.first as? VideoContentVC else { return }
        if let prev = previousViewControllers.first as? VideoContentVC {
            emitViewEnd(for: prev)
            pool.release(prev.playerKit)
        }
        currentIndex = visible.index
        visible.attachAndPlay()
        viewStart = CFAbsoluteTimeGetCurrent()
        // Preload next and previous for instant flicks
        let nextIndex = currentIndex + 1
        if nextIndex < items.count { pool.preloadNext(items[nextIndex].hlsUrl) }
        let prevIndex = currentIndex - 1
        if prevIndex >= 0 { pool.preloadNext(items[prevIndex].hlsUrl) }
    }

    private func emitViewEnd(for vc: VideoContentVC) {
        let dwellMs = Int((CFAbsoluteTimeGetCurrent() - viewStart) * 1000)
        let pos = vc.playerKit.positionSeconds
        let dur = max(vc.playerKit.durationSeconds, 0.1)
        let pct = Int((pos / dur) * 100.0)
        eventBus.enqueue(TelemetryEvent(name: "view_end", props: ["video_id": AnyCodable(vc.item.id), "dwell_ms": AnyCodable(dwellMs), "percent_complete": AnyCodable(pct)]))
        flushDebouncer.call { self.eventBus.flushNow() }
    }
}

// MARK: - Overlays

final class ScrubOverlay: UIView {
    let imageView = UIImageView()
    let timeLabel = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Scrub Preview"
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 8; clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let stack = UIStackView(arrangedSubviews: [imageView, timeLabel])
        stack.axis = .vertical; stack.spacing = 6; stack.alignment = .center
        addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalToConstant: 120),
            imageView.heightAnchor.constraint(equalToConstant: 68)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class RetryOverlay: UIView {
    let label = UILabel()
    var onRetry: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Playback error. Tap to retry."
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 8; clipsToBounds = true
        label.text = "Playback error. Tap to retry"
        label.textColor = .white; label.font = .systemFont(ofSize: 14, weight: .semibold)
        addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(retry))
        addGestureRecognizer(tap)
        isHidden = true
    }
    @objc private func retry() { onRetry?() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Video Content VC

final class VideoContentVC: UIViewController {
    let index: Int
    let item: VideoItem
    let playerKit: AVPlayerKit
    private let container = UIView()
    private weak var pool: PlayerPool?
    private let eventBus: EventBus
    private let thumbnailProvider: ThumbnailProvider
    private let flushDebouncer: Debouncer

    fileprivate var isPlaying = false
    private var wasPlayingBeforeScrub = false
    private var lastThumbAt = CFAbsoluteTimeGetCurrent()

    private let longPress = UILongPressGestureRecognizer()
    private let scrubOverlay = ScrubOverlay()
    private let retryOverlay = RetryOverlay()

    init(index: Int, item: VideoItem, playerKit: AVPlayerKit, pool: PlayerPool, eventBus: EventBus, thumbnailProvider: ThumbnailProvider, flushDebouncer: Debouncer) {
        self.index = index; self.item = item; self.playerKit = playerKit; self.pool = pool
        self.eventBus = eventBus; self.thumbnailProvider = thumbnailProvider; self.flushDebouncer = flushDebouncer
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        container.frame = view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.isAccessibilityElement = true
        container.accessibilityLabel = "Video \(item.id)"
        view.addSubview(container)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        container.addGestureRecognizer(tap)

        longPress.minimumPressDuration = 0.25
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        container.addGestureRecognizer(longPress)

        scrubOverlay.isHidden = true
        view.addSubview(scrubOverlay)

        retryOverlay.onRetry = { [weak self] in self?.retryPlayback() }
        view.addSubview(retryOverlay)
        retryOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            retryOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            retryOverlay.widthAnchor.constraint(equalToConstant: 240),
            retryOverlay.heightAnchor.constraint(equalToConstant: 80)
        ])

        playerKit.attach(to: container)
        playerKit.onEvent = { [weak self] name, _ in
            guard let self = self else { return }
            switch name {
            case "playback_start": self.isPlaying = true; self.retryOverlay.isHidden = true
            case "paused", "ended": self.isPlaying = false
            case "error", "playback_error":
                self.isPlaying = false
                self.retryOverlay.isHidden = false
                self.eventBus.enqueue(TelemetryEvent(name: "playback_error", props: ["video_id": AnyCodable(self.item.id)]))
                self.flushDebouncer.call { self.eventBus.flushNow() }
            default: break
            }
        }
        playerKit.prepare(hlsUrl: item.hlsUrl, initialBitrateCapKbps: 700)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w: CGFloat = 160, h: CGFloat = 120
        scrubOverlay.frame = CGRect(x: (view.bounds.width - w)/2, y: view.safeAreaInsets.top + 20, width: w, height: h)
    }

    func attachAndPlay() { playerKit.attach(to: container); play() }

    func play() { playerKit.play(); isPlaying = true }
    func pause() { playerKit.pause(); isPlaying = false }

    @objc private func handleTap() {
        if isPlaying { pause() } else { play() }
        eventBus.enqueue(TelemetryEvent(name: "tap_play_pause", props: ["playing": AnyCodable(isPlaying)]))
        flushDebouncer.call { self.eventBus.flushNow() }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        let loc = gr.location(in: container)
        let width = max(container.bounds.width, 1)
        let dur = max(playerKit.durationSeconds, 0.1)
        let fraction = min(max(loc.x / width, 0), 1)
        let target = Double(fraction) * dur

        switch gr.state {
        case .began:
            wasPlayingBeforeScrub = isPlaying
            pause()
            scrubOverlay.isHidden = false
            eventBus.enqueue(TelemetryEvent(name: "preview_scrub_start"))
        case .changed:
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastThumbAt > 0.12 {
                lastThumbAt = now
                requestThumb(seconds: target)
            }
        case .ended, .cancelled, .failed:
            playerKit.seek(ms: Int64(target * 1000))
            if wasPlayingBeforeScrub { play() }
            scrubOverlay.isHidden = true
            eventBus.enqueue(TelemetryEvent(name: "preview_scrub_commit", props: ["seconds": AnyCodable(Int(target))]))
        default: break
        }
        scrubOverlay.timeLabel.text = timeString(seconds: target)
        flushDebouncer.call { self.eventBus.flushNow() }
    }

    private func requestThumb(seconds: Double) {
        thumbnailProvider.thumbnail(for: item, at: seconds) { [weak self] img in
            self?.scrubOverlay.imageView.image = img
        }
    }

    private func timeString(seconds: Double) -> String {
        let s = Int(seconds) % 60, m = Int(seconds) / 60
        return String(format: "%02d:%02d", m, s)
    }

    private func retryPlayback() {
        retryOverlay.isHidden = true
        playerKit.prepare(hlsUrl: item.hlsUrl, initialBitrateCapKbps: 700)
        play()
    }

    deinit { pool?.release(playerKit) }
}
