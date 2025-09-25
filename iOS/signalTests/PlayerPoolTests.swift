@testable import signal
import XCTest

final class PlayerPoolTests: XCTestCase {

    final class StubEventBus: EventBusProtocol {
        func enqueue(_ event: TelemetryEvent) {}
        func flushNow() {}
    }

    private func makeManifest(id: String) -> MediaManifest {
        return MediaManifest(
            videoId: id,
            durationMs: 30_000,
            hlsUrl: URL(string: "https://example.com/\(id).m3u8")!,
            posterUrl: URL(string: "https://example.com/\(id).jpg")!,
            thumbnailVttUrl: URL(string: "https://example.com/\(id).vtt")!,
            ladder: [],
            loudnessLufs: -16.0,
            createdAt: Date()
        )
    }

    func testAcquireReturnsPreloadedPlayer() {
        let pool = PlayerPool(size: 3, eventBus: StubEventBus())
        let manifest = makeManifest(id: "v1")

        pool.preloadNext(manifest)

        let player = pool.acquire(for: "v1")

        XCTAssertTrue(player.isPrepared(for: "v1"), "Expected preloaded player to still be prepared for video id v1")
    }

    func testRecycleKeepsPreviousSlot() {
        let pool = PlayerPool(size: 3, eventBus: StubEventBus())
        let current = makeManifest(id: "current")
        let previous = makeManifest(id: "previous")

        pool.preloadNext(current)
        let currentPlayer = pool.acquire(for: "current")
        XCTAssertTrue(currentPlayer.isPrepared(for: "current"))

        pool.preloadPrevious(previous)
        let previousPrepared = pool.acquire(for: "previous")
        XCTAssertTrue(previousPrepared.isPrepared(for: "previous"))

        pool.recycleDetachedPlayer(previousPrepared, for: "previous")
        pool.preloadNext(current)
        let reusedPlayer = pool.acquire(for: "current")

        XCTAssertTrue(reusedPlayer.isPrepared(for: "current"))
    }
}
