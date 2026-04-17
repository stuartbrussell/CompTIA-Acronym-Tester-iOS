import Foundation
import SwiftUI
import Combine

/// The single source of truth for the quiz state.
///
/// Mirrors the Python app's `AcronymTester` class: loads one or more CSV
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
        reload()
    }

    // MARK: - Loading pipeline

    /// Reload from disk. Called on startup, when lists/strict mode change, or
    /// when the user taps Reload.
    func reload() {
        let lists = AcronymList.all.filter { enabledListIDs.contains($0.id) }

        var rawRows: [RawAcronymRow] = []
        for list in lists {
            rawRows += CSVLoader.loadRows(resourceName: list.resourceName)
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

    /// Merge rows that share the same key (case-insensitive) into a single
    /// `Acronym` with all distinct values/links stacked.
    private static func mergeDuplicates(_ rows: [RawAcronymRow]) -> [Acronym] {
        // Sort by key (case-insensitive) so duplicates are adjacent.
        let sorted = rows.sorted {
            let a = $0.key.lowercased()
            let b = $1.key.lowercased()
            if a != b { return a < b }
            return $0.value.lowercased() < $1.value.lowercased()
        }

        var out: [Acronym] = []
        for row in sorted {
            if var last = out.last,
               last.key.caseInsensitiveCompare(row.key) == .orderedSame {
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

    /// Rebuild `activeItems` from `allItems` honoring the current length filter.
    private func applyLengthFilter() {
        if lengthFilter == 0 {
            activeItems = allItems
        } else {
            activeItems = allItems.filter { $0.key.count == lengthFilter }
        }
        results = Array(repeating: .untested, count: activeItems.count)
        currentIndex = 0
        revealed = false

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

    // MARK: - Marking

    func mark(_ result: Result) {
        guard results.indices.contains(currentIndex) else { return }
        results[currentIndex] = result
        if reviewMode && !hasAnyIncorrect {
            reviewMode = false
        }
    }

    func currentResult() -> Result {
        results.indices.contains(currentIndex) ? results[currentIndex] : .untested
    }

    func resetScore() {
        results = Array(repeating: .untested, count: activeItems.count)
        currentIndex = 0
        revealed = false
        if reviewMode { reviewMode = false }
    }

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

// MARK: - UserDefaults-backed settings

private enum Defaults {
    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let enabledListIDs = "enabledListIDs"
        static let strictMode = "strictMode"
        static let lengthFilter = "lengthFilter"
        static let reviewMode = "reviewMode"
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
}
