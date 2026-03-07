import SwiftUI

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Focused value: any text field focused

private struct AnyTextFieldFocusedKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var anyTextFieldFocused: Bool? {
        get { self[AnyTextFieldFocusedKey.self] }
        set { self[AnyTextFieldFocusedKey.self] = newValue }
    }
}
