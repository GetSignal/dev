//
//  VideoPageViewController.swift
//  signal
//
//  UIPageViewController wrapper for vertical video paging
//

import UIKit
import SwiftUI

class VideoPageViewController: UIPageViewController {
    
    // MARK: - Properties
    private var videoControllers: [VideoPlayerViewController] = []
    private var currentIndex: Int = 0
    private weak var feedDelegate: VideoPageDelegate?
    var eventBus: EventBusProtocol?
    var playerPool: PlayerPool?
    
    // Keep a lightweight signature of items to detect changes
    private var itemIds: [String] = []
    
    // MARK: - Initialization
    init() {
        super.init(transitionStyle: .scroll, navigationOrientation: .vertical, options: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        delegate = self
        view.backgroundColor = .black
        
        // Disable bounce for snap feel
        if let scrollView = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.bounces = false
            scrollView.decelerationRate = .fast // Fast deceleration for snap feel
        }
    }
    
    // MARK: - Public Methods
    func setup(with items: [VideoItem], delegate: VideoPageDelegate?) {
        self.feedDelegate = delegate
        
        // Create view controllers for each video
        videoControllers = items.map { item in
            let vc = VideoPlayerViewController(videoItem: item, eventBus: eventBus)
            vc.delegate = self
            return vc
        }
        itemIds = items.map { $0.videoId }
        print("[PageVC] setup items=\(items.count) controllers=\(videoControllers.count)")
        
        // Set initial view controller
        if let firstVC = videoControllers.first {
            setViewControllers([firstVC], direction: .forward, animated: false)
            // Defer notifying SwiftUI to avoid state mutations during update
            DispatchQueue.main.async { [weak self] in self?.feedDelegate?.didShowVideo(at: 0) }
        }
    }
    
    func updateItems(_ items: [VideoItem], currentIndex: Int) {
        let newIds = items.map { $0.videoId }
        guard !newIds.isEmpty else { return }

        // Map existing controllers by videoId for reuse
        var existingById: [String: VideoPlayerViewController] = [:]
        for vc in videoControllers { existingById[vc.videoId] = vc }

        // Determine current displayed VC's id, if any
        var displayedId: String?
        if let currentVC = viewControllers?.first as? VideoPlayerViewController {
            displayedId = currentVC.videoId
        }

        // Build new controllers array reusing where possible
        var newControllers: [VideoPlayerViewController] = []
        for item in items {
            if let reuse = existingById[item.videoId] {
                newControllers.append(reuse)
            } else {
                let vc = VideoPlayerViewController(videoItem: item, eventBus: eventBus)
                vc.delegate = self
                newControllers.append(vc)
            }
        }

        // Compute target index: keep current if still present; else clamp to provided currentIndex
        var targetIndex: Int = 0
        if let did = displayedId, let idx = newControllers.firstIndex(where: { $0.videoId == did }) {
            targetIndex = idx
        } else {
            targetIndex = max(0, min(currentIndex, newControllers.count - 1))
        }

        // Apply updates
        videoControllers = newControllers
        itemIds = newIds
        print("[PageVC] update items=\(items.count) controllers=\(videoControllers.count) displayedId=\(displayedId ?? "nil") targetIndex=\(targetIndex)")

        // Only reset if different from currently displayed VC instance
        if let displayed = viewControllers?.first as? VideoPlayerViewController,
           displayed !== videoControllers[targetIndex] {
            setViewControllers([videoControllers[targetIndex]], direction: .forward, animated: false)
        }
        self.currentIndex = targetIndex
        // Defer notifying SwiftUI to avoid state mutations during update
        DispatchQueue.main.async { [weak self] in self?.feedDelegate?.didShowVideo(at: targetIndex) }

        // Prefetch next
        if targetIndex < videoControllers.count - 1 {
            feedDelegate?.shouldPrefetchVideo(at: targetIndex + 1)
        }
    }
    
    func moveToVideo(at index: Int) {
        guard index >= 0 && index < videoControllers.count else { return }
        
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        let targetVC = videoControllers[index]
        
        setViewControllers([targetVC], direction: direction, animated: true) { [weak self] _ in
            self?.currentIndex = index
            self?.feedDelegate?.didShowVideo(at: index)
        }
    }
}

// MARK: - UIPageViewControllerDataSource
extension VideoPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let currentVC = viewController as? VideoPlayerViewController,
              let currentIndex = videoControllers.firstIndex(where: { $0 === currentVC }),
              currentIndex > 0 else {
            print("[PageVC] before: no previous (index resolve failed or at start)")
            return nil
        }
        print("[PageVC] before: returning index \(currentIndex - 1) of \(videoControllers.count)")
        return videoControllers[currentIndex - 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let currentVC = viewController as? VideoPlayerViewController,
              let currentIndex = videoControllers.firstIndex(where: { $0 === currentVC }),
              currentIndex < videoControllers.count - 1 else {
            print("[PageVC] after: no next (index resolve failed or at end)")
            return nil
        }
        print("[PageVC] after: returning index \(currentIndex + 1) of \(videoControllers.count)")
        return videoControllers[currentIndex + 1]
    }
}

// MARK: - UIPageViewControllerDelegate
extension VideoPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let currentVC = viewControllers?.first as? VideoPlayerViewController,
              let index = videoControllers.firstIndex(where: { $0 === currentVC }) else {
            return
        }
        
        // Pause previous video
        if let previousVC = previousViewControllers.first as? VideoPlayerViewController {
            previousVC.pause()
        }
        
        // Autoplay is handled by PlayerKit when attached and ready
        
        currentIndex = index
        feedDelegate?.didShowVideo(at: index)
        
        // Prefetch next video
        if index < videoControllers.count - 1 {
            feedDelegate?.shouldPrefetchVideo(at: index + 1)
        }
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        // Prepare for transition
        if let nextVC = pendingViewControllers.first as? VideoPlayerViewController,
           let nextIndex = videoControllers.firstIndex(where: { $0 === nextVC }) {
            feedDelegate?.willShowVideo(at: nextIndex)
        }
    }
}

// MARK: - VideoPlayerDelegate
extension VideoPageViewController: VideoPlayerDelegate {
    func videoPlayerDidTap(_ controller: VideoPlayerViewController) {
        controller.togglePlayPause()
        // If user paused, ensure no hidden players are running
        if controller.isPlayingNow == false {
            playerPool?.pauseAll()
        }
    }
    
    func videoPlayerDidLongPress(_ controller: VideoPlayerViewController, state: UIGestureRecognizer.State, location: CGPoint) {
        controller.handleLongPress(state: state, location: location)
    }
}

// MARK: - Protocols
protocol VideoPageDelegate: AnyObject {
    func didShowVideo(at index: Int)
    func willShowVideo(at index: Int)
    func shouldPrefetchVideo(at index: Int)
}

protocol VideoPlayerDelegate: AnyObject {
    func videoPlayerDidTap(_ controller: VideoPlayerViewController)
    func videoPlayerDidLongPress(_ controller: VideoPlayerViewController, state: UIGestureRecognizer.State, location: CGPoint)
}

// MARK: - UIPageViewController SwiftUI Wrapper
struct VideoPageView: UIViewControllerRepresentable {
    let items: [VideoItem]
    let playerPool: PlayerPool
    let eventBus: EventBusProtocol
    @Binding var currentIndex: Int
    var onPrefetch: ((Int) -> Void)
    
    func makeUIViewController(context: Context) -> VideoPageViewController {
        let controller = VideoPageViewController()
        controller.eventBus = eventBus
        controller.playerPool = playerPool
        controller.setup(with: items, delegate: context.coordinator)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoPageViewController, context: Context) {
        uiViewController.updateItems(items, currentIndex: currentIndex)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VideoPageDelegate {
        let parent: VideoPageView
        
        init(_ parent: VideoPageView) {
            self.parent = parent
        }
        
        func didShowVideo(at index: Int) {
            parent.currentIndex = index
        }
        
        func willShowVideo(at index: Int) {
            // Prepare player
        }
        
        func shouldPrefetchVideo(at index: Int) {
            guard index < parent.items.count else { return }
            parent.onPrefetch(index)
        }
    }
}
