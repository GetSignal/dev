//
//  MediaManifest.swift
//  signal
//
//  Media manifest model as defined in Agent Guide section 3.1
//

import Foundation

struct MediaManifest: Codable {
    let videoId: String
    let durationMs: Int64
    let hlsUrl: URL
    let posterUrl: URL
    let thumbnailVttUrl: URL
    let ladder: [QualityLevel]
    let loudnessLufs: Double
    let createdAt: Date
    
    struct QualityLevel: Codable {
        let height: Int
        let bitrate: Int
    }
    
    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case durationMs = "duration_ms"
        case hlsUrl = "hls_url"
        case posterUrl = "poster_url"
        case thumbnailVttUrl = "thumbnail_vtt_url"
        case ladder
        case loudnessLufs = "loudness_lufs"
        case createdAt = "created_at"
    }
}

extension MediaManifest {
    var duration: TimeInterval {
        return Double(durationMs) / 1000.0
    }
    
    func qualityLevel(forHeight height: Int) -> QualityLevel? {
        return ladder.first { $0.height == height }
    }
    
    var lowestQuality: QualityLevel? {
        return ladder.min { $0.bitrate < $1.bitrate }
    }
    
    var highestQuality: QualityLevel? {
        return ladder.max { $0.bitrate < $1.bitrate }
    }
}