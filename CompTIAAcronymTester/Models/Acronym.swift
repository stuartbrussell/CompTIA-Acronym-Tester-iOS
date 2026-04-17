import Foundation

/// A single acronym entry ready for display.
///
/// When multiple source rows share the same `key` (case-insensitive), their
/// distinct `value`/`link` pairs are merged into the parallel `values` and
/// `links` arrays. This mirrors the Python app's duplicate-merging logic.
struct Acronym: Identifiable, Hashable {
    let id = UUID()
    let key: String
    var values: [String]
    var links: [String]

    /// Expansion text as shown on the card: multiple meanings stacked.
    var joinedValue: String {
        values.joined(separator: "\n")
    }

    /// URLs to open when the user taps Browse.
    var urls: [URL] {
        links.compactMap { URL(string: $0) }
    }
}
