import Foundation

struct Transcript: Codable {
    let version: Int
    let recordingId: String
    let createdAt: Date
    var speakers: [TranscriptSpeaker]
    var segments: [TranscriptSegment]

    static let currentVersion = 1

    /// Render as markdown for copy/export
    func renderMarkdown() -> String {
        var md = ""
        let speakerMap = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })

        for segment in segments {
            let speaker = speakerMap[segment.speakerId]
            let name = speaker?.name ?? segment.speakerId
            let start = Self.formatTimestamp(segment.startTime)
            md += "**[\(start)] \(name):**\n\(segment.text)\n\n"
        }
        return md
    }

    /// Plain text for search
    var plainText: String {
        segments.map { $0.text }.joined(separator: " ")
    }

    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct TranscriptSpeaker: Codable, Identifiable {
    let id: String
    var name: String
    var profileId: String?
    var color: Int  // index into a predefined color palette

    static let colors: [String] = [
        "#4A90D9", "#D94A4A", "#4AD97A", "#D9A84A",
        "#9B4AD9", "#4AD9D9", "#D94A9B", "#7AD94A"
    ]
}

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    let speakerId: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Float

    init(speakerId: String, startTime: TimeInterval, endTime: TimeInterval, text: String, confidence: Float = 0) {
        self.id = UUID()
        self.speakerId = speakerId
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
    }
}
