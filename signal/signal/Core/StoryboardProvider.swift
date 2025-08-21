//
//  StoryboardProvider.swift
//  signal
//
//  Provides storyboard frames for scrub preview
//  - LRU cache of ~24 images
//  - Neighbor prefetch
//  - ~8 FPS throttling
//

import Foundation
import UIKit

class StoryboardProvider {
    
    // MARK: - Properties
    private var vttCues: [VTTCue] = []
    private let imageCache = NSCache<NSString, UIImage>()
    private let spriteCache = NSCache<NSURL, UIImage>()
    private var loadingTasks: [URL: Task<UIImage?, Never>] = [:]
    
    private let maxCacheSize = 24 // LRU cache size as per spec
    private let throttleInterval: TimeInterval = 1.0 / 8.0 // ~8 FPS as per spec
    private var lastRequestTime: Date = Date.distantPast
    
    private let session: URLSession
    
    // MARK: - Initialization
    init() {
        // Configure cache
        imageCache.countLimit = maxCacheSize
        spriteCache.countLimit = 10 // Cache sprite sheets
        
        // Configure URL session with caching
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024, // 50MB memory
            diskCapacity: 256 * 1024 * 1024,  // 256MB disk as per spec
            diskPath: "signal_storyboard_cache"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Interface
    func loadVTT(from url: URL) async {
        do {
            vttCues = try await WebVTTParser.load(from: url)
            
            // Prefetch first few sprite sheets
            if !vttCues.isEmpty {
                await prefetchNeighbors(around: 0)
            }
        } catch {
            print("[StoryboardProvider] Failed to load VTT: \(error)")
        }
    }
    
    func frame(at time: TimeInterval, throttled: Bool = true) async -> UIImage? {
        // Apply throttling if requested
        if throttled {
            let now = Date()
            let timeSinceLastRequest = now.timeIntervalSince(lastRequestTime)
            if timeSinceLastRequest < throttleInterval {
                // Too soon, return cached or nil
                if let cachedImage = getCachedFrame(at: time) {
                    return cachedImage
                }
                return nil
            }
            lastRequestTime = now
        }
        
        // Find the cue for this time
        guard let cue = WebVTTParser.findCue(at: time, in: vttCues) else {
            return nil
        }
        
        // Check cache first
        let cacheKey = "\(cue.imageUrl.absoluteString)_\(cue.rect)" as NSString
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            // Prefetch neighbors in background
            Task {
                await prefetchNeighbors(around: time)
            }
            return cachedImage
        }
        
        // Load and crop the sprite
        guard let spriteImage = await loadSprite(from: cue.imageUrl) else {
            return nil
        }
        
        let croppedImage = cropImage(spriteImage, rect: cue.rect)
        
        // Cache the result
        if let croppedImage = croppedImage {
            imageCache.setObject(croppedImage, forKey: cacheKey)
        }
        
        // Prefetch neighbors
        Task {
            await prefetchNeighbors(around: time)
        }
        
        return croppedImage
    }
    
    // MARK: - Private Methods
    private func getCachedFrame(at time: TimeInterval) -> UIImage? {
        guard let cue = WebVTTParser.findCue(at: time, in: vttCues) else {
            return nil
        }
        
        let cacheKey = "\(cue.imageUrl.absoluteString)_\(cue.rect)" as NSString
        return imageCache.object(forKey: cacheKey)
    }
    
    private func loadSprite(from url: URL) async -> UIImage? {
        // Check sprite cache first
        let cacheKey = url as NSURL
        if let cachedSprite = spriteCache.object(forKey: cacheKey) {
            return cachedSprite
        }
        
        // Check if already loading
        if let existingTask = loadingTasks[url] {
            return await existingTask.value
        }
        
        // Create new loading task
        let task = Task<UIImage?, Never> {
            do {
                let (data, _) = try await session.data(from: url)
                if let image = UIImage(data: data) {
                    self.spriteCache.setObject(image, forKey: cacheKey)
                    return image
                }
            } catch {
                print("[StoryboardProvider] Failed to load sprite: \(error)")
            }
            return nil
        }
        
        loadingTasks[url] = task
        let result = await task.value
        loadingTasks.removeValue(forKey: url)
        
        return result
    }
    
    private func cropImage(_ image: UIImage, rect: CGRect) -> UIImage? {
        // Ensure we're working with the correct scale
        let scale = image.scale
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let cgImage = image.cgImage?.cropping(to: scaledRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }
    
    private func prefetchNeighbors(around time: TimeInterval) async {
        // Find current cue index
        guard let currentCue = WebVTTParser.findCue(at: time, in: vttCues),
              let currentIndex = vttCues.firstIndex(where: { $0.startTime == currentCue.startTime }) else {
            return
        }
        
        // Prefetch ±2 cues around current
        let prefetchRange = max(0, currentIndex - 2)...min(vttCues.count - 1, currentIndex + 2)
        
        for index in prefetchRange {
            let cue = vttCues[index]
            let cacheKey = "\(cue.imageUrl.absoluteString)_\(cue.rect)" as NSString
            
            // Skip if already cached
            if imageCache.object(forKey: cacheKey) != nil {
                continue
            }
            
            // Load sprite and cache frame
            if let spriteImage = await loadSprite(from: cue.imageUrl),
               let croppedImage = cropImage(spriteImage, rect: cue.rect) {
                imageCache.setObject(croppedImage, forKey: cacheKey)
            }
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        vttCues.removeAll()
        imageCache.removeAllObjects()
        spriteCache.removeAllObjects()
        
        // Cancel loading tasks
        for task in loadingTasks.values {
            task.cancel()
        }
        loadingTasks.removeAll()
    }
}

// MARK: - Scrub Preview View
class ScrubPreviewView: UIView {
    private let imageView = UIImageView()
    private let timeLabel = UILabel()
    private let provider: StoryboardProvider
    
    init(provider: StoryboardProvider) {
        self.provider = provider
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.8)
        layer.cornerRadius = 8
        clipsToBounds = true
        
        // Image view
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        // Time label
        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        timeLabel.textAlignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            imageView.heightAnchor.constraint(equalToConstant: 90),
            
            timeLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    func updatePreview(at time: TimeInterval) {
        Task {
            if let frame = await provider.frame(at: time) {
                await MainActor.run {
                    imageView.image = frame
                    timeLabel.text = formatTime(time)
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}