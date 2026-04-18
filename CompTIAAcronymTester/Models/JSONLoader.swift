import Foundation

/// Loads acronym rows from a bundled JSON file.
///
/// The JSON schema matches the files generated from the canonical CSVs:
/// ```json
/// [
///   { "itemkey": "AAA",
///     "itemvalue": "Authentication, Authorization, and Accounting",
///     "itemlink": "https://en.wikipedia.org/wiki/...",
///     "strict": true },
///   ...
/// ]
/// ```
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

    static func loadRows(resourceName: String, bundle: Bundle = .main) -> [RawAcronymRow] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            assertionFailure("Missing bundled JSON: \(resourceName).json")
            return []
        }
        guard let data = try? Data(contentsOf: url) else {
            assertionFailure("Unable to read JSON: \(url.path)")
            return []
        }
        do {
            let entries = try JSONDecoder().decode([JSONEntry].self, from: data)
            return entries.map {
                RawAcronymRow(key: $0.itemkey,
                              value: $0.itemvalue,
                              link: $0.itemlink,
                              strict: $0.strict ?? true)
            }
        } catch {
            assertionFailure("JSON decode error in \(resourceName).json: \(error)")
            return []
        }
    }

    // MARK: - Private decodable shape

    private struct JSONEntry: Decodable {
        let itemkey: String
        let itemvalue: String
        let itemlink: String
        let strict: Bool?   // optional so files without the field still load cleanly
    }
}
