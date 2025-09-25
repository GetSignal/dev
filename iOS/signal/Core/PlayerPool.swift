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
    private struct Slot {
        let id: String
        let player: PlayerKit
    }

    private var players: [PlayerKit] = []
    private var availablePlayers: Set<PlayerKit> = []
    private var currentSlot: Slot?
    private var nextSlot: Slot?
    private var previousSlot: Slot?
    
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
    func acquire(for videoId: String) -> PlayerKit {
        if let slot = currentSlot, slot.id == videoId {
            return slot.player
        }

        let priorCurrent = currentSlot
        let resolvedSlot: Slot

        if let slot = nextSlot, slot.id == videoId {
            resolvedSlot = slot
            nextSlot = nil
        } else if let slot = previousSlot, slot.id == videoId {
            resolvedSlot = slot
            previousSlot = nil
        } else {
            let player = takeAvailablePlayer()
            resolvedSlot = Slot(id: videoId, player: player)
        }

        currentSlot = resolvedSlot
        promoteToPreviousIfNeeded(previousCandidate: priorCurrent, newCurrentId: videoId)
        return resolvedSlot.player
    }

    // MARK: - Prefetching
    func preloadNext(_ manifest: MediaManifest) {
        guard currentSlot?.id != manifest.videoId else { return }

        if let slot = nextSlot, slot.id == manifest.videoId {
            prepare(slot.player, with: manifest, autoPlay: false, bufferDuration: prefetchDuration)
            return
        }

        if let slot = nextSlot { releaseToAvailable(slot) }

        if let slot = previousSlot, slot.id == manifest.videoId {
            previousSlot = nil
            prepare(slot.player, with: manifest, autoPlay: false, bufferDuration: prefetchDuration)
            nextSlot = Slot(id: manifest.videoId, player: slot.player)
        } else {
            let player = takeAvailablePlayer()
            prepare(player, with: manifest, autoPlay: false, bufferDuration: prefetchDuration)
            nextSlot = Slot(id: manifest.videoId, player: player)
        }
    }

    func preloadPrevious(_ manifest: MediaManifest?) {
        guard let manifest = manifest else { return }

        guard currentSlot?.id != manifest.videoId else { return }

        if let slot = previousSlot, slot.id == manifest.videoId {
            prepare(slot.player, with: manifest, autoPlay: false, bufferDuration: 3.0)
            return
        }

        if let slot = previousSlot { releaseToAvailable(slot) }

        if let slot = nextSlot, slot.id == manifest.videoId {
            nextSlot = nil
            prepare(slot.player, with: manifest, autoPlay: false, bufferDuration: 3.0)
            previousSlot = Slot(id: manifest.videoId, player: slot.player)
        } else {
            let player = takeAvailablePlayer()
            prepare(player, with: manifest, autoPlay: false, bufferDuration: 3.0)
            previousSlot = Slot(id: manifest.videoId, player: player)
        }
    }

    // MARK: - Transition Management
    func promoteNext() -> PlayerKit? {
        guard let id = nextSlot?.id else { return nil }
        return acquire(for: id)
    }

    func promotePrevious() -> PlayerKit? {
        guard let id = previousSlot?.id else { return nil }
        return acquire(for: id)
    }

    // MARK: - Lifecycle
    func pauseAll() {
        currentSlot?.player.pause()
        nextSlot?.player.pause()
        previousSlot?.player.pause()
        availablePlayers.forEach { $0.pause() }
    }

    func cleanup() {
        if let slot = currentSlot { releaseToAvailable(slot) }
        if let slot = nextSlot { releaseToAvailable(slot) }
        if let slot = previousSlot { releaseToAvailable(slot) }
        currentSlot = nil
        nextSlot = nil
        previousSlot = nil
        availablePlayers.formUnion(players)
    }

    // MARK: - Status
    var currentPlayer: PlayerKit? {
        return currentSlot?.player
    }

    var isNextReady: Bool {
        return nextSlot != nil
    }

    var isPreviousReady: Bool {
        return previousSlot != nil
    }

    func recycleDetachedPlayer(_ player: PlayerKit, for itemId: String?) {
        guard let itemId = itemId else {
            player.cleanup()
            availablePlayers.insert(player)
            return
        }

        if let slot = currentSlot, slot.player === player {
            return
        }
        if let slot = previousSlot, slot.player === player, slot.id == itemId {
            return
        }
        if let slot = nextSlot, slot.player === player, slot.id == itemId {
            return
        }

        player.cleanup()
        availablePlayers.insert(player)
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
        
        nextSlot?.player.prefetch(adjustedDuration)
    }
}

// MARK: - Helpers
private extension PlayerPool {
    func takeAvailablePlayer() -> PlayerKit {
        if let player = availablePlayers.first {
            availablePlayers.remove(player)
            return player
        }
        let player = PlayerKit()
        player.setEventBus(eventBus)
        players.append(player)
        return player
    }

    private func prepare(_ player: PlayerKit, with manifest: MediaManifest, autoPlay: Bool, bufferDuration: TimeInterval) {
        player.prepare(hlsUrl: manifest.hlsUrl, videoId: manifest.videoId, initialBitrateCapKbps: 700, autoPlay: autoPlay)
        player.prefetch(bufferDuration)
        if !autoPlay {
            player.primeForBuffering()
        }
    }

    private func releaseToAvailable(_ slot: Slot) {
        slot.player.cleanup()
        availablePlayers.insert(slot.player)
    }

    private func promoteToPreviousIfNeeded(previousCandidate: Slot?, newCurrentId: String) {
        guard let candidate = previousCandidate, candidate.id != newCurrentId else { return }
        if let existingPrev = previousSlot {
            releaseToAvailable(existingPrev)
        }
        previousSlot = candidate
    }
}
