//
//  ManifestStore.swift
//  signal
//
//  Centralized manifest resolver with in-memory coalescing and URLCache-backed HTTP.
//  Honors CDN caching headers and avoids duplicate per-cell fetches.
//

import Foundation

actor ManifestStore {
    private var cache: [URL: MediaManifest] = [:]
    private var inFlight: [URL: Task<MediaManifest, Error>] = [:]
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            // Respect large on-disk cache as per spec
            if URLCache.shared.diskCapacity < 256 * 1024 * 1024 {
                URLCache.shared = URLCache(
                    memoryCapacity: 32 * 1024 * 1024,
                    diskCapacity: 256 * 1024 * 1024,
                    diskPath: "signal_http_cache"
                )
            }
            config.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: config)
        }
    }

    func manifest(for url: URL) async throws -> MediaManifest {
        if let m = cache[url] { return m }

        if let task = inFlight[url] { return try await task.value }

        let task = Task<MediaManifest, Error> {
            let (data, _) = try await self.session.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(MediaManifest.self, from: data)
            await self.store(manifest, for: url)
            return manifest
        }
        inFlight[url] = task
        defer { inFlight.removeValue(forKey: url) }
        return try await task.value
    }

    private func store(_ manifest: MediaManifest, for url: URL) {
        cache[url] = manifest
    }

    func prefetch(_ url: URL) async {
        _ = try? await manifest(for: url)
    }

    func clear() {
        cache.removeAll()
        inFlight.removeAll()
    }
}
