import CoreGraphics
import Foundation
import SwiftUI

// MARK: - AnnotationKind

enum AnnotationKind: String, Codable, CaseIterable {
    case text      = "Text"
    case line      = "Line"
    case arrow     = "Arrow"
    case rectangle = "Rectangle"
    case circle    = "Circle"

    var systemImage: String {
        switch self {
        case .text:      return "text.bubble"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .circle:    return "circle"
        }
    }
}

// MARK: - TextFontWeight

enum TextFontWeight: String, Codable, CaseIterable {
    case regular  = "Regular"
    case semibold = "Semibold"
    case bold     = "Bold"
    case heavy    = "Heavy"

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:  return .regular
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        }
    }

    /// CoreText weight value used when building CATextLayer fonts for export.
    var ctWeight: CGFloat {
        switch self {
        case .regular:  return 0.0
        case .semibold: return 0.3
        case .bold:     return 0.4
        case .heavy:    return 0.56
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

    // Text-only styling
    var textColor: CodableColor         // foreground colour
    var fontSize: CGFloat               // fraction of video width (e.g. 0.03 = 3 %)
    var fontWeight: TextFontWeight
    var showBackground: Bool
    var backgroundColor: CodableColor
    var backgroundOpacity: Double       // 0…1
    var backgroundCornerRadius: CGFloat

    // MARK: Memberwise init (keeps call sites from older code working via defaults)

    init(id: UUID, kind: AnnotationKind, text: String = "",
         startTime: Double, duration: Double,
         position: CGPoint, endPosition: CGPoint,
         strokeColor: CodableColor, strokeWidth: CGFloat,
         textColor: CodableColor         = .init(red: 1, green: 1, blue: 1),
         fontSize: CGFloat               = 0.03,
         fontWeight: TextFontWeight      = .bold,
         showBackground: Bool            = false,
         backgroundColor: CodableColor  = .init(red: 0, green: 0, blue: 0),
         backgroundOpacity: Double       = 0.6,
         backgroundCornerRadius: CGFloat = 6) {
        self.id = id; self.kind = kind; self.text = text
        self.startTime = startTime; self.duration = duration
        self.position = position; self.endPosition = endPosition
        self.strokeColor = strokeColor; self.strokeWidth = strokeWidth
        self.textColor = textColor; self.fontSize = fontSize; self.fontWeight = fontWeight
        self.showBackground = showBackground; self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.backgroundCornerRadius = backgroundCornerRadius
    }

    // MARK: Codable — decodeIfPresent for new fields so old saved data still loads

    enum CodingKeys: String, CodingKey {
        case id, kind, text, startTime, duration, position, endPosition
        case strokeColor, strokeWidth
        case textColor, fontSize, fontWeight
        case showBackground, backgroundColor, backgroundOpacity, backgroundCornerRadius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self,            forKey: .id)
        kind        = try c.decode(AnnotationKind.self,  forKey: .kind)
        text        = try c.decode(String.self,          forKey: .text)
        startTime   = try c.decode(Double.self,          forKey: .startTime)
        duration    = try c.decode(Double.self,          forKey: .duration)
        position    = try c.decode(CGPoint.self,         forKey: .position)
        endPosition = try c.decode(CGPoint.self,         forKey: .endPosition)
        strokeColor = try c.decode(CodableColor.self,    forKey: .strokeColor)
        strokeWidth = try c.decode(CGFloat.self,         forKey: .strokeWidth)
        // New fields with safe defaults for old data
        textColor             = try c.decodeIfPresent(CodableColor.self,    forKey: .textColor)             ?? .init(red: 1, green: 1, blue: 1)
        fontSize              = try c.decodeIfPresent(CGFloat.self,         forKey: .fontSize)              ?? 0.03
        fontWeight            = try c.decodeIfPresent(TextFontWeight.self,  forKey: .fontWeight)            ?? .bold
        showBackground        = try c.decodeIfPresent(Bool.self,            forKey: .showBackground)        ?? false
        backgroundColor       = try c.decodeIfPresent(CodableColor.self,    forKey: .backgroundColor)       ?? .init(red: 0, green: 0, blue: 0)
        backgroundOpacity     = try c.decodeIfPresent(Double.self,          forKey: .backgroundOpacity)     ?? 0.6
        backgroundCornerRadius = try c.decodeIfPresent(CGFloat.self,        forKey: .backgroundCornerRadius) ?? 6
    }
}
