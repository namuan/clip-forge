import CoreGraphics
import Foundation

// MARK: - AnnotationKind

enum AnnotationKind: String, Codable, CaseIterable {
    case text      = "Text"
    case line      = "Line"
    case rectangle = "Rectangle"
    case circle    = "Circle"

    var systemImage: String {
        switch self {
        case .text:      return "text.bubble"
        case .line:      return "line.diagonal"
        case .rectangle: return "rectangle"
        case .circle:    return "circle"
        }
    }
}

// MARK: - Annotation

struct Annotation: Identifiable, Codable {
    let id: UUID
    var kind: AnnotationKind
    var text: String           // used by .text kind
    var startTime: Double
    var duration: Double
    var position: CGPoint      // normalized 0…1 — text anchor | shape start/center
    var endPosition: CGPoint   // normalized 0…1 — shape end point (unused for text)
    var strokeColor: CodableColor
    var strokeWidth: CGFloat
}
