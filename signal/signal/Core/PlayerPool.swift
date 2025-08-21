//
//  PlayerPool.swift
//  signal
//
//  Manages a pool of 2-3 PlayerKit instances for smooth transitions
//  Implements prefetch strategy: current + 5-8s of next video
//

import Foundation
import UIKit

class PlayerPool {
    
    // MARK: - Properties
    private let poolSize: Int
    private let eventBus: EventBusProtocol
    private var players: [PlayerKit] = []
    private var availablePlayers: Set<PlayerKit> = []
    private var activePlayer: PlayerKit?
    private var nextPlayer: PlayerKit?
    private var previousPlayer: PlayerKit?
    
    private let prefetchDuration: TimeInterval = 5.0 // Prefetch 5-8s of next as per spec
    
    // MARK: - Initialization
    init(size: Int = 3, eventBus: EventBusProtocol) {
        self.poolSize = min(max(size, 2), 3) // Clamp between 2-3 as per spec
        self.eventBus = eventBus
        setupPool()
    }
    
    private func setupPool() {
        for _ in 0..<poolSize {
            let player = PlayerKit()
            player.setEventBus(eventBus)
            players.append(player)
            availablePlayers.insert(player)
        }
    }
    
    // MARK: - Player Management
    func acquire() -> PlayerKit? {
        // If we have an available player, use it
        if let player = availablePlayers.first {
            availablePlayers.remove(player)
            activePlayer = player
            return player
        }
        
        // If no available players, reuse the oldest one (not current or next)
        if let player = previousPlayer {
            player.cleanup()
            previousPlayer = nil
            activePlayer = player
            return player
        }
        
        // Fallback: create a new player if needed (shouldn't happen with proper management)
        let player = PlayerKit()
        player.setEventBus(eventBus)
        players.append(player)
        activePlayer = player
        return player
    }
    
    func release(_ player: PlayerKit) {
        player.cleanup()
        availablePlayers.insert(player)
        
        if player === activePlayer {
            activePlayer = nil
        } else if player === nextPlayer {
            nextPlayer = nil
        } else if player === previousPlayer {
            previousPlayer = nil
        }
    }
    
    // MARK: - Prefetching
    func preloadNext(_ manifest: MediaManifest) {
        // Get or create next player
        if nextPlayer == nil {
            if let player = availablePlayers.first {
                availablePlayers.remove(player)
                nextPlayer = player
            } else if previousPlayer != nil {
                // Reuse previous player for next
                previousPlayer?.cleanup()
                nextPlayer = previousPlayer
                previousPlayer = nil
            }
        }
        
        // Prepare the next player
        nextPlayer?.prepare(
            hlsUrl: manifest.hlsUrl,
            videoId: manifest.videoId,
            initialBitrateCapKbps: 700
        )
        
        // Prefetch initial seconds
        nextPlayer?.prefetch(prefetchDuration)
    }
    
    func preloadPrevious(_ manifest: MediaManifest?) {
        guard let manifest = manifest else { return }
        
        // Only preload previous if we have available players
        guard availablePlayers.count > 0 || (poolSize > 2 && previousPlayer == nil) else { return }
        
        if previousPlayer == nil {
            if let player = availablePlayers.first {
                availablePlayers.remove(player)
                previousPlayer = player
            }
        }
        
        previousPlayer?.prepare(
            hlsUrl: manifest.hlsUrl,
            videoId: manifest.videoId,
            initialBitrateCapKbps: 700
        )
        
        // Prefetch less for previous (user less likely to go back)
        previousPlayer?.prefetch(3.0)
    }
    
    // MARK: - Transition Management
    func promoteNext() -> PlayerKit? {
        // Move current to previous
        if let current = activePlayer {
            current.cleanup()
            if previousPlayer != nil {
                release(previousPlayer!)
            }
            previousPlayer = current
        }
        
        // Promote next to current
        activePlayer = nextPlayer
        nextPlayer = nil
        
        return activePlayer
    }
    
    func promotePrevious() -> PlayerKit? {
        // Move current to next
        if let current = activePlayer {
            current.cleanup()
            if nextPlayer != nil {
                release(nextPlayer!)
            }
            nextPlayer = current
        }
        
        // Promote previous to current
        activePlayer = previousPlayer
        previousPlayer = nil
        
        return activePlayer
    }
    
    // MARK: - Lifecycle
    func pauseAll() {
        players.forEach { $0.pause() }
    }
    
    func cleanup() {
        players.forEach { $0.cleanup() }
        availablePlayers.removeAll()
        activePlayer = nil
        nextPlayer = nil
        previousPlayer = nil
    }
    
    // MARK: - Status
    var currentPlayer: PlayerKit? {
        return activePlayer
    }
    
    var isNextReady: Bool {
        return nextPlayer != nil
    }
    
    var isPreviousReady: Bool {
        return previousPlayer != nil
    }
}

// MARK: - Prefetch Strategy
extension PlayerPool {
    /// Implements adaptive prefetch based on bandwidth and user behavior
    func updatePrefetchStrategy(basedOn bandwidth: Double) {
        // Adjust prefetch duration based on available bandwidth
        // Higher bandwidth = more aggressive prefetch
        let adjustedDuration: TimeInterval
        
        if bandwidth > 5_000_000 { // > 5 Mbps
            adjustedDuration = 8.0 // Prefetch up to 8s
        } else if bandwidth > 2_000_000 { // > 2 Mbps
            adjustedDuration = 5.0 // Default 5s
        } else {
            adjustedDuration = 3.0 // Conservative 3s
        }
        
        nextPlayer?.prefetch(adjustedDuration)
    }
}