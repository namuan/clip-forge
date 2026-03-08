import Foundation

/// A single timed subtitle entry with start/end timestamps and text.
struct SubtitleSegment: Codable, Sendable, Identifiable {
    let id: UUID
    let start: TimeInterval   // seconds from media start
    let end: TimeInterval     // seconds from media start
    var text: String

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    /// Duration of the subtitle in seconds.
    var duration: TimeInterval { end - start }
}
