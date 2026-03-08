import CoreGraphics
import Foundation

enum SubtitleStylePreset: String, CaseIterable, Codable, Identifiable {
    case classic
    case tikTok
    case tikTokYellow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Default"
        case .tikTok: return "TikTok"
        case .tikTokYellow: return "TikTok Yellow"
        }
    }

    var subtitleStyle: SubtitleStyle {
        switch self {
        case .classic: return .classic
        case .tikTok: return .tikTok
        case .tikTokYellow: return .tikTokYellow
        }
    }
}

struct SubtitleStyle: Codable, Equatable {
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var outlineColor: CodableColor
    var outlineWidth: CGFloat
    var backgroundColor: CodableColor
    var backgroundOpacity: CGFloat
    var backgroundPadding: CGFloat
    var shadowColor: CodableColor
    var shadowBlur: CGFloat
    var shadowOffset: CGSize
    var verticalPosition: CGFloat
    var horizontalMargin: CGFloat
    var autoScaleToFit: Bool
}

extension SubtitleStyle {
    static let classic = SubtitleStyle(
        fontName: "HelveticaNeue",
        fontSize: 41,
        textColor: .init(red: 1, green: 1, blue: 1),
        outlineColor: .init(red: 0, green: 0, blue: 0),
        outlineWidth: 0,
        backgroundColor: .init(red: 0, green: 0, blue: 0),
        backgroundOpacity: 0.72,
        backgroundPadding: 14,
        shadowColor: .init(red: 0, green: 0, blue: 0),
        shadowBlur: 0,
        shadowOffset: .zero,
        verticalPosition: 0.88,
        horizontalMargin: 0.06,
        autoScaleToFit: true
    )

    static let tikTok = SubtitleStyle(
        fontName: "SFPro-Bold",
        fontSize: 52,
        textColor: .init(red: 1, green: 1, blue: 1),
        outlineColor: .init(red: 0, green: 0, blue: 0),
        outlineWidth: 7,
        backgroundColor: .init(red: 0, green: 0, blue: 0),
        backgroundOpacity: 0.78,
        backgroundPadding: 18,
        shadowColor: .init(red: 0, green: 0, blue: 0),
        shadowBlur: 5,
        shadowOffset: CGSize(width: 0, height: 4),
        verticalPosition: 0.87,
        horizontalMargin: 0.06,
        autoScaleToFit: true
    )

    static let tikTokYellow = SubtitleStyle(
        fontName: "SFPro-Bold",
        fontSize: 52,
        textColor: .init(red: 1.0, green: 0.95, blue: 0.0),
        outlineColor: .init(red: 0, green: 0, blue: 0),
        outlineWidth: 7,
        backgroundColor: .init(red: 0, green: 0, blue: 0),
        backgroundOpacity: 0.75,
        backgroundPadding: 18,
        shadowColor: .init(red: 0, green: 0, blue: 0),
        shadowBlur: 5,
        shadowOffset: CGSize(width: 0, height: 4),
        verticalPosition: 0.87,
        horizontalMargin: 0.06,
        autoScaleToFit: true
    )
}
