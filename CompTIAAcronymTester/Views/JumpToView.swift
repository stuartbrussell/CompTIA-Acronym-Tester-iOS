import SwiftUI

/// Search sheet — lets the user type an acronym (or prefix) and jump straight
/// to that card in the active deck.
///
/// Opened via the magnifying-glass button in the QuizView toolbar.
/// Dismisses automatically after the user taps an entry.
///
/// Uses a plain TextField (rather than .searchable) so that @FocusState can
/// programmatically raise the keyboard the moment the sheet opens.
///
/// ## Two-section matching
///
/// **Top section — prefix matches:** the acronym starts with the query string
/// (same behaviour as before).
///
/// **Bottom section — non-contiguous matches:** every letter in the query
/// appears *in order* somewhere in the acronym, but the letters need not be
/// adjacent and the first query letter need not be the first letter of the
/// acronym (subsequence match). Items already shown in the top section are
/// excluded so there is no duplication.
struct JumpToView: View {
    @EnvironmentObject private var store: QuizStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // MARK: - Match helpers

    typealias Match = (index: Int, item: Acronym)

    /// True when the acronym key starts with `q` (q must be non-empty).
    private func isPrefixMatch(key: String, q: String) -> Bool {
        key.hasPrefix(q)
    }

    /// True when every character of `q` appears in `key` in order (subsequence),
    /// but the match does NOT start at the very beginning — i.e. it is a
    /// non-contiguous match that is not already a prefix match.
    private func isSubsequenceOnlyMatch(key: String, q: String) -> Bool {
        guard !isPrefixMatch(key: key, q: q) else { return false }
        var queryIdx = q.startIndex
        for ch in key {
            if queryIdx == q.endIndex { break }
            if ch == q[queryIdx] {
                queryIdx = q.index(after: queryIdx)
            }
        }
        return queryIdx == q.endIndex
    }

    private var q: String {
        query.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var prefixMatches: [Match] {
        if q.isEmpty {
            // No query → show all items in the top section.
            return store.activeItems.enumerated().map { ($0.offset, $0.element) }
        }
        return store.activeItems.enumerated().compactMap { offset, item in
            isPrefixMatch(key: item.key.uppercased(), q: q) ? (offset, item) : nil
        }
    }

    private var subsequenceMatches: [Match] {
        guard !q.isEmpty else { return [] }
        return store.activeItems.enumerated().compactMap { offset, item in
            isSubsequenceOnlyMatch(key: item.key.uppercased(), q: q) ? (offset, item) : nil
        }
    }

    private var hasNoMatches: Bool {
        !q.isEmpty && prefixMatches.isEmpty && subsequenceMatches.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Acronym", text: $query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.search)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Results
                if hasNoMatches {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        // Top section — prefix / full list
                        Section {
                            ForEach(prefixMatches, id: \.item.id) { match in
                                rowButton(for: match)
                            }
                        } header: {
                            if !q.isEmpty {
                                Text("Starts with \(q)")
                            }
                        }

                        // Bottom section — non-contiguous (only when querying)
                        if !subsequenceMatches.isEmpty {
                            Section("Letters in order") {
                                ForEach(subsequenceMatches, id: \.item.id) { match in
                                    rowButton(for: match)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Jump To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Small delay lets the sheet finish its presentation animation
                // before raising the keyboard, which avoids a layout stutter.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    searchFocused = true
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowButton(for match: Match) -> some View {
        Button {
            store.jumpTo(index: match.index)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(match.item.key)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(match.item.joinedValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    JumpToView()
        .environmentObject(QuizStore())
}
