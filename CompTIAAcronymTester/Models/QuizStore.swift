import Foundation
import SwiftUI
import Combine

/// The single source of truth for the quiz state.
///
/// Mirrors the Python app's `AcronymTester` class: loads one or more JSON
/// files, merges duplicate acronyms, supports strict-mode filtering, length
/// filtering, shuffling, prev/next navigation, per-item correctness tracking,
/// review mode (cycle only through incorrect items), and score display.
///
/// Note: intentionally not marked `@MainActor`. Under Xcode 26's strict
/// concurrency, `@MainActor` on an `ObservableObject` prevents synthesis of
/// the `objectWillChange` publisher because the protocol requirement must be
/// reachable from non-isolated contexts. All mutation paths here originate
/// from SwiftUI view actions (tap, toggle, picker change, sheet dismissal),
/// which already run on the main actor — so the isolation annotation was
/// redundant anyway.
final class QuizStore: ObservableObject {

    enum Result: Equatable {
        case untested, correct, incorrect
    }

    // MARK: - Configuration (persisted in UserDefaults)

    @Published var enabledListIDs: Set<String> {
        didSet {
            Defaults.enabledListIDs = enabledListIDs
            reload()
        }
    }

    @Published var strictMode: Bool {
        didSet {
            Defaults.strictMode = strictMode
            reload()
        }
    }

    /// `0` = all lengths; otherwise filter to acronyms of that character length.
    @Published var lengthFilter: Int {
        didSet {
            Defaults.lengthFilter = lengthFilter
            applyLengthFilter()
        }
    }

    /// Review mode: next/prev only visit items marked `.incorrect`.
    @Published var reviewMode: Bool {
        didSet {
            Defaults.reviewMode = reviewMode
            jumpToFirstReviewItemIfNeeded()
        }
    }

    /// When enabled, tested acronyms and their marks are persisted across
    /// launches. On relaunch the deck is reconstructed with tested items
    /// behind the current position and untested items (freshly shuffled) ahead.
    @Published var sessionRestoreEnabled: Bool {
        didSet {
            Defaults.sessionRestoreEnabled = sessionRestoreEnabled
            if !sessionRestoreEnabled {
                clearSavedSession()
            }
        }
    }

    // MARK: - Published state

    /// All acronyms from the enabled lists, after strict filter and duplicate merge.
    @Published private(set) var allItems: [Acronym] = []
    /// Subset after length filter; this is what the user navigates through.
    @Published private(set) var activeItems: [Acronym] = []
    /// Per-item correctness, parallel-indexed to `activeItems`.
    @Published private(set) var results: [Result] = []
    @Published private(set) var currentIndex: Int = 0
    /// Whether the expansion is currently revealed on the card.
    @Published var revealed: Bool = false

    // MARK: - Computed

    var currentItem: Acronym? {
        guard activeItems.indices.contains(currentIndex) else { return nil }
        return activeItems[currentIndex]
    }

    var correctCount: Int { results.filter { $0 == .correct }.count }
    var incorrectCount: Int { results.filter { $0 == .incorrect }.count }

    /// All acronym lengths present in `allItems`, plus 0 for "all".
    var availableLengths: [Int] {
        var lengths = Set<Int>()
        for item in allItems { lengths.insert(item.key.count) }
        return [0] + lengths.sorted()
    }

    var hasAnyIncorrect: Bool {
        results.contains(.incorrect)
    }

    // MARK: - Init

    init() {
        // Read persisted settings; fall back to "all lists enabled" on first run.
        self.enabledListIDs = Defaults.enabledListIDs ?? Set(AcronymList.all.map(\.id))
        self.strictMode = Defaults.strictMode
        self.lengthFilter = Defaults.lengthFilter
        self.reviewMode = Defaults.reviewMode
        self.sessionRestoreEnabled = Defaults.sessionRestoreEnabled
        reload()
    }

    // MARK: - Loading pipeline

    /// Reload from disk. Called on startup, when lists/strict mode change, or
    /// when the user taps Reload.
    func reload() {
        let lists = AcronymList.all.filter { enabledListIDs.contains($0.id) }

        var rawRows: [RawAcronymRow] = []
        for list in lists {
            rawRows += JSONLoader.loadRows(resourceName: list.resourceName)
        }

        if strictMode {
            rawRows = rawRows.filter { $0.strict }
        }

        var merged = Self.mergeDuplicates(rawRows)
        merged.shuffle()
        allItems = merged

        // Re-validate length filter against the new list of lengths.
        // Setting lengthFilter triggers its didSet → applyLengthFilter(),
        // which is what we want. No recursion back into reload().
        if !availableLengths.contains(lengthFilter) {
            lengthFilter = 0
        } else {
            applyLengthFilter()
        }
    }

    /// Clear saved session and reload from scratch. Use this for an explicit
    /// "start over" action so the restored state is not re-applied.
    func reshuffleAndReset() {
        clearSavedSession()
        reload()
    }

    /// Merge rows that share the same key (case-insensitive) into a single
    /// `Acronym` with all distinct values/links stacked.
    private static func mergeDuplicates(_ rows: [RawAcronymRow]) -> [Acronym] {
        // Sort by exact key so same-cased duplicates are adjacent.
        // Case matters: "KB" (kilobyte) and "Kb" (kilobit) are distinct entries.
        let sorted = rows.sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return $0.value.lowercased() < $1.value.lowercased()
        }

        var out: [Acronym] = []
        for row in sorted {
            if var last = out.last, last.key == row.key {
                if !last.values.contains(row.value) {
                    last.values.append(row.value)
                    last.links.append(row.link)
                    out[out.count - 1] = last
                }
            } else {
                out.append(Acronym(key: row.key, values: [row.value], links: [row.link]))
            }
        }
        return out
    }

    /// Rebuild `activeItems` from `allItems` honoring the current length filter,
    /// then overlay any saved session progress on top.
    private func applyLengthFilter() {
        if lengthFilter == 0 {
            activeItems = allItems
        } else {
            activeItems = allItems.filter { $0.key.count == lengthFilter }
        }
        results = Array(repeating: .untested, count: activeItems.count)
        currentIndex = 0
        revealed = false

        // Overlay saved session progress (no-op if disabled or nothing saved).
        restoreSessionIfNeeded()

        // If review mode is on but no incorrect exists yet, turn it off so
        // the user can actually see items.
        if reviewMode && !hasAnyIncorrect {
            reviewMode = false  // this triggers didSet → persists & jumps, no-op here
        }
    }

    // MARK: - Navigation

    func next() {
        guard !activeItems.isEmpty else { return }
        if reviewMode {
            if let idx = nextIncorrectIndex(after: currentIndex) {
                currentIndex = idx
            }
        } else {
            currentIndex = (currentIndex + 1) % activeItems.count
        }
        revealed = false
    }

    func previous() {
        guard !activeItems.isEmpty else { return }
        if reviewMode {
            if let idx = previousIncorrectIndex(before: currentIndex) {
                currentIndex = idx
            }
        } else {
            currentIndex = (currentIndex - 1 + activeItems.count) % activeItems.count
        }
        revealed = false
    }

    func toggleReveal() {
        revealed.toggle()
    }

    func resetCurrentResult() {
        mark(.untested)
    }

    // MARK: - Marking

    func mark(_ result: Result) {
        guard results.indices.contains(currentIndex) else { return }
        results[currentIndex] = result
        saveSession()
        if reviewMode && !hasAnyIncorrect {
            reviewMode = false
        }
    }

    func currentResult() -> Result {
        results.indices.contains(currentIndex) ? results[currentIndex] : .untested
    }

    /// Jump directly to a specific card by its index in `activeItems`.
    /// Resets the revealed state; preserves existing correctness marks.
    func jumpTo(index: Int) {
        guard activeItems.indices.contains(index) else { return }
        currentIndex = index
        revealed = false
        // Turn off review mode so the user can freely navigate from this card.
        if reviewMode { reviewMode = false }
    }

    func resetScore() {
        clearSavedSession()
        results = Array(repeating: .untested, count: activeItems.count)
        currentIndex = 0
        revealed = false
        if reviewMode { reviewMode = false }
    }

    // MARK: - Session persistence

    /// Persist the ordered list of tested acronyms and their results as JSON
    /// in the app's Documents directory. Only tested items are saved; untested
    /// items are shuffled fresh on restore.
    private func saveSession() {
        guard sessionRestoreEnabled else { return }
        var entries: [SessionEntry] = []
        for (i, item) in activeItems.enumerated() {
            let r = results[i]
            guard r != .untested else { continue }
            entries.append(SessionEntry(k: item.key, r: r == .correct ? 1 : 2))
        }
        do {
            if entries.isEmpty {
                clearSavedSession()
            } else {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: Self.sessionFileURL, options: .atomic)
            }
        } catch {
            // Non-fatal: session simply won't be restored next launch.
            print("QuizStore: failed to save session — \(error)")
        }
    }

    /// Reconstruct deck order from the saved session JSON file.
    ///
    /// Tested items (in the order the user worked through them) are placed
    /// before `currentIndex`; untested items are shuffled and placed after.
    /// Items in the saved session that no longer exist in `activeItems`
    /// (e.g. because a list was disabled) are silently dropped.
    private func restoreSessionIfNeeded() {
        guard sessionRestoreEnabled else { return }
        guard let data = try? Data(contentsOf: Self.sessionFileURL),
              let entries = try? JSONDecoder().decode([SessionEntry].self, from: data),
              !entries.isEmpty else { return }

        // Look up acronyms by key for fast access.
        let itemByKey = Dictionary(uniqueKeysWithValues: activeItems.map { ($0.key, $0) })

        // Tested items — in saved order, skipping any no longer in the active set.
        var testedItems:   [Acronym] = []
        var testedResults: [Result]  = []
        for entry in entries {
            guard let item = itemByKey[entry.k] else { continue }
            testedItems.append(item)
            testedResults.append(entry.r == 1 ? .correct : .incorrect)
        }

        guard !testedItems.isEmpty else { return }

        // Untested items — everything not in the saved set, shuffled fresh.
        let testedKeys    = Set(entries.map(\.k))
        let untestedItems = activeItems.filter { !testedKeys.contains($0.key) }.shuffled()

        // Reconstruct deck: tested first, then untested.
        activeItems = testedItems + untestedItems
        results     = testedResults + Array(repeating: .untested, count: untestedItems.count)

        // Land on the first untested item (or wrap to 0 if everything is tested).
        currentIndex = testedItems.count < activeItems.count ? testedItems.count : 0
        revealed = false
    }

    private func clearSavedSession() {
        try? FileManager.default.removeItem(at: Self.sessionFileURL)
    }

    /// Location of the session file in the app's Documents directory.
    private static var sessionFileURL: URL {
        URL.documentsDirectory.appendingPathComponent("session.json")
    }

    // MARK: - Debug helpers

#if DEBUG
    /// Loads all rows from the currently selected lists (no strict or length
    /// filtering) and prints three focused duplicate reports to the Xcode console.
    ///
    /// **Section 1 — duplicate itemKey:** prints every entry in the group plus
    /// its source file. itemValue and itemLink are suppressed when all entries
    /// in the group share the same value/link respectively.
    ///
    /// **Section 2 — duplicate itemValue:** only prints groups where itemKey
    /// or itemLink differs across entries (skips purely redundant cross-file copies).
    ///
    /// **Section 3 — duplicate itemLink:** only prints groups where itemKey
    /// or itemValue differs across entries.
    func printDuplicates() {

        struct Tagged {
            let row: RawAcronymRow
            let source: String      // e.g. "APlus.json"
        }

        // Load all rows from selected lists, tagged with their source filename.
        let lists = AcronymList.all.filter { enabledListIDs.contains($0.id) }
        var tagged: [Tagged] = []
        for list in lists {
            for row in JSONLoader.loadRows(resourceName: list.resourceName) {
                tagged.append(Tagged(row: row, source: "\(list.resourceName).json"))
            }
        }

        // Returns groups of ≥2 entries sharing the same lowercased key,
        // sorted by that key.
        func groups(by key: (Tagged) -> String) -> [[Tagged]] {
            var map: [String: [Tagged]] = [:]
            for item in tagged { map[key(item).lowercased(), default: []].append(item) }
            return map.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }.map(\.value)
        }

        // Convenience: number of distinct values for a field across a group.
        func distinct(_ items: [Tagged], _ field: (Tagged) -> String) -> Int {
            Set(items.map { field($0) }).count
        }

        // ── Section 1: duplicate itemKey ─────────────────────────────────────
        let keyGroups = groups { $0.row.key }
        print("\n=== Duplicate itemKey — \(keyGroups.isEmpty ? "none" : "\(keyGroups.count) group(s)") ===")
        for items in keyGroups {
            let showValue = distinct(items, { $0.row.value }) > 1
            let showLink  = distinct(items, { $0.row.link  }) > 1
            for item in items.sorted(by: { $0.source < $1.source }) {
                var line = item.row.key
                if showValue { line += ": \(item.row.value)" }
                if showLink  { line += "  \(item.row.link)" }
                print("  \(line)  [\(item.source)]")
            }
            print("")
        }

        // ── Section 2: duplicate itemValue, only when key or link differs ────
        let valueGroups = groups { $0.row.value }
            .filter { distinct($0, { $0.row.key  }) > 1
                   || distinct($0, { $0.row.link }) > 1 }
        print("\n=== Duplicate itemValue (key or link differs) — \(valueGroups.isEmpty ? "none" : "\(valueGroups.count) group(s)") ===")
        for items in valueGroups {
            let showKey  = distinct(items, { $0.row.key  }) > 1
            let showLink = distinct(items, { $0.row.link }) > 1
            for item in items.sorted(by: { $0.source < $1.source }) {
                var line = item.row.value
                if showKey  { line += "  (key: \(item.row.key))" }
                if showLink { line += "  \(item.row.link)" }
                print("  \(line)  [\(item.source)]")
            }
            print("")
        }

        // ── Section 3: duplicate itemLink, only when key or value differs ────
        let linkGroups = groups { $0.row.link }
            .filter { distinct($0, { $0.row.key   }) > 1
                   || distinct($0, { $0.row.value }) > 1 }
        print("\n=== Duplicate itemLink (key or value differs) — \(linkGroups.isEmpty ? "none" : "\(linkGroups.count) group(s)") ===")
        for items in linkGroups {
            let showKey   = distinct(items, { $0.row.key   }) > 1
            let showValue = distinct(items, { $0.row.value }) > 1
            for item in items.sorted(by: { $0.source < $1.source }) {
                var line = item.row.link
                if showKey   { line += "  (key: \(item.row.key))" }
                if showValue { line += "  \(item.row.value)" }
                print("  \(line)  [\(item.source)]")
            }
            print("")
        }
    }
#endif

    // MARK: - Review mode helpers

    private func jumpToFirstReviewItemIfNeeded() {
        guard reviewMode else { return }
        if let idx = firstIncorrectIndex() {
            currentIndex = idx
            revealed = false
        } else {
            reviewMode = false
        }
    }

    private func firstIncorrectIndex() -> Int? {
        results.firstIndex(of: .incorrect)
    }

    private func nextIncorrectIndex(after index: Int) -> Int? {
        guard !results.isEmpty else { return nil }
        let n = results.count
        for offset in 1...n {
            let i = (index + offset) % n
            if results[i] == .incorrect { return i }
        }
        return nil
    }

    private func previousIncorrectIndex(before index: Int) -> Int? {
        guard !results.isEmpty else { return nil }
        let n = results.count
        for offset in 1...n {
            let i = (index - offset + n) % n
            if results[i] == .incorrect { return i }
        }
        return nil
    }
}

// MARK: - Session file entry

/// One tested-acronym record written to `session.json`.
private struct SessionEntry: Codable {
    /// The acronym key, e.g. "TCP".
    let k: String
    /// Result: 1 = correct, 2 = incorrect.
    let r: Int
}

// MARK: - UserDefaults-backed settings

private enum Defaults {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let enabledListIDs        = "enabledListIDs"
        static let strictMode            = "strictMode"
        static let lengthFilter          = "lengthFilter"
        static let reviewMode            = "reviewMode"
        static let sessionRestoreEnabled = "sessionRestoreEnabled"
    }

    static var enabledListIDs: Set<String>? {
        get {
            guard let arr = defaults.array(forKey: Keys.enabledListIDs) as? [String] else {
                return nil
            }
            return Set(arr)
        }
        set {
            if let v = newValue {
                defaults.set(Array(v), forKey: Keys.enabledListIDs)
            } else {
                defaults.removeObject(forKey: Keys.enabledListIDs)
            }
        }
    }

    static var strictMode: Bool {
        get { defaults.bool(forKey: Keys.strictMode) }
        set { defaults.set(newValue, forKey: Keys.strictMode) }
    }

    static var lengthFilter: Int {
        get { defaults.integer(forKey: Keys.lengthFilter) }
        set { defaults.set(newValue, forKey: Keys.lengthFilter) }
    }

    static var reviewMode: Bool {
        get { defaults.bool(forKey: Keys.reviewMode) }
        set { defaults.set(newValue, forKey: Keys.reviewMode) }
    }

    /// Defaults to `true` for new installs (feature is on by default).
    static var sessionRestoreEnabled: Bool {
        get { defaults.object(forKey: Keys.sessionRestoreEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.sessionRestoreEnabled) }
    }

}
