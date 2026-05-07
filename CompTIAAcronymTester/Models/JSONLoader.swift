import Foundation

/// Loads acronym rows from a JSON file.
///
/// **File format (versioned envelope — current)**
/// ```json
/// {
///   "version": 1,
///   "acronyms": [
///     { "itemkey": "AAA",
///       "itemvalue": "Authentication, Authorization, and Accounting",
///       "itemlink": "https://en.wikipedia.org/wiki/...",
///       "strict": true },
///     ...
///   ]
/// }
/// ```
///
/// **Reading priority**
/// 1. `<Documents>/<resourceName>.json` — written there by `UpdateManager` after a
///    successful download.
/// 2. `<Bundle>/<resourceName>.json` — the seed copy shipped with the app.
///
/// Returns the same `RawAcronymRow` type used by `QuizStore` so the rest of
/// the pipeline is unchanged.

struct RawAcronymRow {
    let key: String
    let value: String
    let link: String
    let strict: Bool
}

enum JSONLoader {

    // MARK: - Public API

    /// Load acronym rows for `resourceName`, preferring the Documents copy.
    static func loadRows(resourceName: String, bundle: Bundle = .main) -> [RawAcronymRow] {
        // 1. Try Documents directory first (downloaded / updated copy).
        let docsURL = URL.documentsDirectory.appendingPathComponent("\(resourceName).json")
        if let rows = loadRows(from: docsURL) {
            return rows
        }
        // 2. Fall back to the bundled seed.
        guard let bundleURL = bundle.url(forResource: resourceName, withExtension: "json") else {
            assertionFailure("Missing bundled JSON: \(resourceName).json")
            return []
        }
        return loadRows(from: bundleURL) ?? []
    }

    /// Return the `version` field from a JSON file at an arbitrary URL,
    /// or `nil` if the file doesn't exist / can't be decoded.
    static func version(at url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(VersionOnlyEnvelope.self, from: data))?.version
    }

    // MARK: - Private helpers

    private static func loadRows(from url: URL) -> [RawAcronymRow]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let envelope = try JSONDecoder().decode(VersionedEnvelope.self, from: data)
            return envelope.acronyms.map {
                RawAcronymRow(key: $0.itemkey,
                              value: $0.itemvalue,
                              link: $0.itemlink,
                              strict: $0.strict ?? true)
            }
        } catch {
            assertionFailure("JSON decode error in \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Decodable shapes

    private struct VersionedEnvelope: Decodable {
        let version: Int
        let acronyms: [JSONEntry]
    }

    private struct VersionOnlyEnvelope: Decodable {
        let version: Int
    }

    private struct JSONEntry: Decodable {
        let itemkey: String
        let itemvalue: String
        let itemlink: String
        let strict: Bool?   // optional so files without the field still load cleanly
    }
}
