import CoreGraphics
import Foundation
import SwiftUI

// MARK: - CodableColor

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }
}

extension Color {
    func toCodable() -> CodableColor {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return CodableColor(red: Double(r), green: Double(g), blue: Double(b))
        #elseif canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return CodableColor(red: Double(ns.redComponent),
                            green: Double(ns.greenComponent),
                            blue: Double(ns.blueComponent))
        #endif
    }
}

// MARK: - BackgroundStyle

enum BackgroundStyle: String, Codable, CaseIterable {
    case gradient    = "Gradient"
    case solid       = "Solid"
    case transparent = "None"
}

// MARK: - BackgroundSettings

struct BackgroundSettings: Codable {
    var style: BackgroundStyle      = .gradient
    var gradientStart: CodableColor = .init(red: 0.44, green: 0.28, blue: 0.88)
    var gradientEnd: CodableColor   = .init(red: 0.18, green: 0.52, blue: 0.92)
    var solidColor: CodableColor    = .init(red: 0.08, green: 0.08, blue: 0.12)
    /// Padding as a fraction of the shorter video dimension (0 = none, 0.15 = 15 %)
    var paddingFraction: CGFloat    = 0.065
    var cornerRadius: CGFloat       = 14
    var shadowOpacity: Float        = 0.50
    var shadowRadius: CGFloat       = 22
}

// MARK: - Presets

extension BackgroundSettings {
    struct Preset: Identifiable {
        let id = UUID()
        let name: String
        var settings: BackgroundSettings
    }

    static let presets: [Preset] = [
        Preset(name: "Iris",     settings: .init(style: .gradient,
            gradientStart: .init(red: 0.44, green: 0.28, blue: 0.88),
            gradientEnd:   .init(red: 0.18, green: 0.52, blue: 0.92))),
        Preset(name: "Sunset",   settings: .init(style: .gradient,
            gradientStart: .init(red: 0.98, green: 0.42, blue: 0.42),
            gradientEnd:   .init(red: 0.99, green: 0.83, blue: 0.35))),
        Preset(name: "Forest",   settings: .init(style: .gradient,
            gradientStart: .init(red: 0.07, green: 0.31, blue: 0.37),
            gradientEnd:   .init(red: 0.44, green: 0.70, blue: 0.50))),
        Preset(name: "Rose",     settings: .init(style: .gradient,
            gradientStart: .init(red: 0.91, green: 0.38, blue: 0.70),
            gradientEnd:   .init(red: 0.99, green: 0.70, blue: 0.50))),
        Preset(name: "Ocean",    settings: .init(style: .gradient,
            gradientStart: .init(red: 0.13, green: 0.60, blue: 0.70),
            gradientEnd:   .init(red: 0.43, green: 0.84, blue: 0.98))),
        Preset(name: "Midnight", settings: .init(style: .gradient,
            gradientStart: .init(red: 0.10, green: 0.11, blue: 0.14),
            gradientEnd:   .init(red: 0.22, green: 0.23, blue: 0.28))),
        Preset(name: "Charcoal", settings: .init(style: .solid,
            solidColor: .init(red: 0.12, green: 0.12, blue: 0.14))),
        Preset(name: "White",    settings: .init(style: .solid,
            solidColor: .init(red: 0.97, green: 0.97, blue: 0.98))),
    ]
}
