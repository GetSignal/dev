//
//  FeedViewModel.swift
//  signal
//
//  View model for the feed, manages data fetching and state
//

import Foundation
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var items: [VideoItem] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: Error?
    
    // MARK: - Properties
    let playerPool: PlayerPool
    let eventBus: EventBusProtocol
    private var cursor: String?
    private var cancellables = Set<AnyCancellable>()
    
    private let apiBaseUrl: String
    
    // MARK: - Initialization
    init() {
        self.apiBaseUrl = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.example.com"
        self.eventBus = EventBus(endpoint: URL(string: "\(apiBaseUrl)/v1/events")!)
        self.playerPool = PlayerPool(size: 3, eventBus: eventBus)
        
        // Load mock data immediately for UI testing
        if ProcessInfo.processInfo.arguments.contains("UI_TESTING") {
            loadMockData()
            isLoading = false
        }
    }
    
    // MARK: - Public Methods
    func loadInitialFeed() async {
        // Skip API loading if UI testing with mock data already loaded
        if ProcessInfo.processInfo.arguments.contains("UI_TESTING") && !items.isEmpty {
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let response = try await fetchFeed(cursor: nil)
            items = response.items
            cursor = response.cursor
            
            // Prefetch first video
            if !items.isEmpty {
                await prefetchVideo(at: 0)
            }
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
            
            // Use mock data for development if API fails
            loadMockData()
        }
    }
    
    func loadMoreItems() async {
        guard !isLoading, let cursor = cursor else { return }
        
        do {
            let response = try await fetchFeed(cursor: cursor)
            items.append(contentsOf: response.items)
            self.cursor = response.cursor
        } catch {
            print("[FeedViewModel] Failed to load more items: \(error)")
        }
    }
    
    func prefetchVideo(at index: Int) async {
        guard index >= 0 && index < items.count else { return }
        
        let item = items[index]
        
        do {
            // Fetch manifest
            let manifest = try await fetchManifest(from: item.mediaManifestUrl)
            
            // Preload with player pool
            playerPool.preloadNext(manifest)
            
            // Prefetch neighbors if bandwidth allows
            if index > 0 {
                let previousItem = items[index - 1]
                if let previousManifest = try? await fetchManifest(from: previousItem.mediaManifestUrl) {
                    playerPool.preloadPrevious(previousManifest)
                }
            }
        } catch {
            print("[FeedViewModel] Failed to prefetch video at index \(index): \(error)")
        }
    }
    
    func videoDidAppear(at index: Int) {
        currentIndex = index
        
        // Load more if approaching end
        if index >= items.count - 3 {
            Task {
                await loadMoreItems()
            }
        }
        
        // Prefetch next video
        if index < items.count - 1 {
            Task {
                await prefetchVideo(at: index + 1)
            }
        }
    }
    
    // MARK: - Private Methods
    private func fetchFeed(cursor: String?) async throws -> FeedResponse {
        var urlComponents = URLComponents(string: "\(apiBaseUrl)/v1/feed")!
        if let cursor = cursor {
            urlComponents.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        
        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(FeedResponse.self, from: data)
    }
    
    private func fetchManifest(from url: URL) async throws -> MediaManifest {
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MediaManifest.self, from: data)
    }
    
    private func loadMockData() {
        // Load mock data for development
        items = [
            VideoItem(
                videoId: "mock1",
                mediaManifestUrl: URL(string: "https://cdn.example.com/mock1/manifest.json")!,
                author: VideoItem.Author(id: "u1", handle: "@user1"),
                stats: VideoItem.Stats(likes: 100, comments: 10, shares: 5)
            ),
            VideoItem(
                videoId: "mock2",
                mediaManifestUrl: URL(string: "https://cdn.example.com/mock2/manifest.json")!,
                author: VideoItem.Author(id: "u2", handle: "@user2"),
                stats: VideoItem.Stats(likes: 200, comments: 20, shares: 10)
            ),
            VideoItem(
                videoId: "mock3",
                mediaManifestUrl: URL(string: "https://cdn.example.com/mock3/manifest.json")!,
                author: VideoItem.Author(id: "u3", handle: "@user3"),
                stats: VideoItem.Stats(likes: 300, comments: 30, shares: 15)
            )
        ]
    }
    
    // MARK: - Player Pool Access
    var currentPlayer: PlayerKit? {
        return playerPool.currentPlayer
    }
    
    func cleanup() {
        playerPool.cleanup()
        eventBus.flushNow()
    }
}