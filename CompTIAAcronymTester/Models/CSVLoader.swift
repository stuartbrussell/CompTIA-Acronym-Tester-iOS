import Foundation

/// A raw row parsed from a CSV file, before duplicate merging.
struct RawAcronymRow {
    let key: String
    let value: String
    let link: String
    let strict: Bool   // defaults to true when the CSV has no "strict" column
}

/// Minimal RFC 4180 CSV reader: supports quoted fields, embedded commas,
/// escaped double-quotes (`""`), and LF / CRLF line endings.
///
/// Sufficient for the acronym CSVs in this app; not a general-purpose parser.
enum CSVLoader {

    /// Load and parse a CSV file from the app bundle by its resource name
    /// (without the `.csv` extension). Returns the raw rows.
    static func loadRows(resourceName: String, bundle: Bundle = .main) -> [RawAcronymRow] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "csv") else {
            assertionFailure("Missing bundled CSV: \(resourceName).csv")
            return []
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Unable to read CSV: \(url.path)")
            return []
        }
        return parse(text: text)
    }

    /// Parse CSV text into raw rows. First non-empty row must be a header
    /// containing `itemkey`, `itemvalue`, `itemlink`, and optionally `strict`.
    static func parse(text: String) -> [RawAcronymRow] {
        let rows = parseRows(text: text)
        guard let header = rows.first else { return [] }

        // Locate expected columns by name; tolerate reordering and missing strict.
        let indexOf: (String) -> Int? = { name in
            header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let keyIdx = indexOf("itemkey"),
              let valueIdx = indexOf("itemvalue"),
              let linkIdx = indexOf("itemlink") else {
            assertionFailure("CSV header missing required columns")
            return []
        }
        let strictIdx = indexOf("strict")

        var out: [RawAcronymRow] = []
        out.reserveCapacity(rows.count - 1)

        for row in rows.dropFirst() {
            // Skip blank trailing rows.
            if row.allSatisfy({ $0.isEmpty }) { continue }
            guard row.count > max(keyIdx, valueIdx, linkIdx) else { continue }

            let strict: Bool
            if let si = strictIdx, si < row.count {
                strict = row[si].lowercased() == "true"
            } else {
                // Network ports.csv has no strict column. Treat as in-scope.
                strict = true
            }

            out.append(RawAcronymRow(
                key: row[keyIdx],
                value: row[valueIdx],
                link: row[linkIdx],
                strict: strict
            ))
        }
        return out
    }

    // MARK: - Low-level parsing

    /// Parse a CSV document into an array of rows, each an array of fields.
    private static func parseRows(text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false

        var iterator = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = nextChar() {
            if inQuotes {
                if c == "\"" {
                    // Look ahead: two quotes in a row → literal quote.
                    if let nxt = iterator.next() {
                        if nxt == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = nxt  // reprocess this character
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
//                case "\r":
//                    // Swallow \r; the following \n (if any) closes the row.
//                    continue
//                case "\n":
                case "\r\n":
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                default:
                    field.append(c)
                }
            }
        }

        // Flush trailing field/row if the file didn't end with a newline.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
