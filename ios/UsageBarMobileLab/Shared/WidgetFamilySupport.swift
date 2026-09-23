import WidgetKit

/// The families each widget kind advertises.
///
/// Declared here, away from the `Widget` types themselves, for one reason: an
/// app extension cannot be `@testable`-imported, so a family list written
/// inline in `Widgets.swift` could never be asserted. Keeping it in shared code
/// means the supported-family contract is testable, and the widgets read from
/// the same list they are tested against.
public enum WidgetFamilySupport {
    /// Overview pairs both providers, so it needs width: the small and medium
    /// Home Screen families, plus the one rectangular Lock Screen family that
    /// can fit two numbers.
    public static let overview: [WidgetFamily] = [
        .systemSmall, .systemMedium, .accessoryRectangular
    ]

    /// A single provider fits anywhere, including the circular and inline
    /// accessories where only one value is legible.
    public static let provider: [WidgetFamily] = [
        .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline
    ]
}
