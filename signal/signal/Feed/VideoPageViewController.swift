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
            let vc = VideoPlayerViewController(videoItem: item)
            vc.delegate = self
            return vc
        }
        
        // Set initial view controller
        if let firstVC = videoControllers.first {
            setViewControllers([firstVC], direction: .forward, animated: false)
            feedDelegate?.didShowVideo(at: 0)
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
              let currentIndex = videoControllers.firstIndex(of: currentVC),
              currentIndex > 0 else {
            return nil
        }
        return videoControllers[currentIndex - 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let currentVC = viewController as? VideoPlayerViewController,
              let currentIndex = videoControllers.firstIndex(of: currentVC),
              currentIndex < videoControllers.count - 1 else {
            return nil
        }
        return videoControllers[currentIndex + 1]
    }
}

// MARK: - UIPageViewControllerDelegate
extension VideoPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let currentVC = viewControllers?.first as? VideoPlayerViewController,
              let index = videoControllers.firstIndex(of: currentVC) else {
            return
        }
        
        // Pause previous video
        if let previousVC = previousViewControllers.first as? VideoPlayerViewController {
            previousVC.pause()
        }
        
        // Play current video
        currentVC.play()
        
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
           let nextIndex = videoControllers.firstIndex(of: nextVC) {
            feedDelegate?.willShowVideo(at: nextIndex)
        }
    }
}

// MARK: - VideoPlayerDelegate
extension VideoPageViewController: VideoPlayerDelegate {
    func videoPlayerDidTap(_ controller: VideoPlayerViewController) {
        controller.togglePlayPause()
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
    
    func makeUIViewController(context: Context) -> VideoPageViewController {
        let controller = VideoPageViewController()
        controller.setup(with: items, delegate: context.coordinator)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoPageViewController, context: Context) {
        // Update if needed
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
            // Trigger prefetch
            guard index < parent.items.count else { return }
            Task {
                // Fetch manifest and prefetch with player pool
            }
        }
    }
}