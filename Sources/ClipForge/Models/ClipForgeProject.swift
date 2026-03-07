import Foundation

struct ClipForgeProject: Codable {
    var name: String
    var videoFileName: String
    var segments: [ZoomSegment]
    var annotations: [Annotation]
    var trimStart: Double
    var trimEnd: Double?
    var playbackSpeed: Double
    var backgroundSettings: BackgroundSettings

    static let fileName = "project.clipforge"
}

enum ProjectError: LocalizedError {
    case noVideo
    case videoFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .noVideo:
            return "No video loaded."
        case .videoFileMissing(let name):
            return "Video file \"\(name)\" not found in the project folder."
        }
    }
}
