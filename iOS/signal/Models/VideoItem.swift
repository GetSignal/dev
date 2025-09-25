//
//  VideoItem.swift
//  signal
//
//  Feed item model representing a video in the feed
//

import Foundation

struct VideoItem: Codable, Identifiable {
    let videoId: String
    let mediaManifestUrl: URL
    let author: Author
    let stats: Stats
    
    struct Author: Codable {
        let id: String
        let handle: String
    }
    
    struct Stats: Codable {
        let likes: Int
        let comments: Int
        let shares: Int
    }
    
    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case mediaManifestUrl = "media_manifest_url"
        case author
        case stats
    }
    
    var id: String { videoId }
}

struct FeedResponse: Codable {
    let cursor: String?
    let items: [VideoItem]
}