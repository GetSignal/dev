//
//  WebVTTParser.swift
//  signal
//
//  Parses WebVTT files for storyboard sprite coordinates
//  Format: sprite.jpg#xywh=x,y,width,height
//

import Foundation
import UIKit

struct VTTCue {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let imageUrl: URL
    let rect: CGRect
}

class WebVTTParser {
    
    static func parse(vttContent: String, baseUrl: URL? = nil) -> [VTTCue] {
        var cues: [VTTCue] = []
        let lines = vttContent.components(separatedBy: .newlines)
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Look for timing line (e.g., "00:00:00.000 --> 00:00:02.000")
            if line.contains("-->") {
                let components = line.components(separatedBy: "-->")
                guard components.count == 2 else {
                    i += 1
                    continue
                }
                
                let startTimeStr = components[0].trimmingCharacters(in: .whitespaces)
                let endTimeStr = components[1].trimmingCharacters(in: .whitespaces)
                
                guard let startTime = parseTime(startTimeStr),
                      let endTime = parseTime(endTimeStr) else {
                    i += 1
                    continue
                }
                
                // Next line should contain the sprite reference
                i += 1
                if i < lines.count {
                    let spriteLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let cue = parseCue(spriteLine: spriteLine, 
                                         startTime: startTime, 
                                         endTime: endTime,
                                         baseUrl: baseUrl) {
                        cues.append(cue)
                    }
                }
            }
            i += 1
        }
        
        return cues
    }
    
    private static func parseTime(_ timeString: String) -> TimeInterval? {
        // Parse format: HH:MM:SS.mmm or MM:SS.mmm
        let components = timeString.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }
        
        var hours: Double = 0
        var minutes: Double = 0
        var seconds: Double = 0
        
        if components.count == 3 {
            // HH:MM:SS.mmm
            hours = Double(components[0]) ?? 0
            minutes = Double(components[1]) ?? 0
            seconds = Double(components[2]) ?? 0
        } else if components.count == 2 {
            // MM:SS.mmm
            minutes = Double(components[0]) ?? 0
            seconds = Double(components[1]) ?? 0
        }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    private static func parseCue(spriteLine: String, 
                                 startTime: TimeInterval, 
                                 endTime: TimeInterval,
                                 baseUrl: URL?) -> VTTCue? {
        // Parse format: sprite.jpg#xywh=x,y,width,height
        let components = spriteLine.components(separatedBy: "#xywh=")
        guard components.count == 2 else { return nil }
        
        let imagePath = components[0]
        let rectString = components[1]
        
        // Parse rectangle coordinates
        let coords = rectString.components(separatedBy: ",")
        guard coords.count == 4,
              let x = Double(coords[0]),
              let y = Double(coords[1]),
              let width = Double(coords[2]),
              let height = Double(coords[3]) else {
            return nil
        }
        
        // Construct image URL
        let imageUrl: URL
        if let baseUrl = baseUrl {
            imageUrl = baseUrl.appendingPathComponent(imagePath)
        } else if let url = URL(string: imagePath) {
            imageUrl = url
        } else {
            return nil
        }
        
        return VTTCue(
            startTime: startTime,
            endTime: endTime,
            imageUrl: imageUrl,
            rect: CGRect(x: x, y: y, width: width, height: height)
        )
    }
    
    static func findCue(at time: TimeInterval, in cues: [VTTCue]) -> VTTCue? {
        return cues.first { cue in
            time >= cue.startTime && time < cue.endTime
        }
    }
}

// MARK: - Async Loading
extension WebVTTParser {
    static func load(from url: URL) async throws -> [VTTCue] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "VTTParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode VTT content"])
        }
        
        // Extract base URL for relative sprite paths
        let baseUrl = url.deletingLastPathComponent()
        return parse(vttContent: content, baseUrl: baseUrl)
    }
}