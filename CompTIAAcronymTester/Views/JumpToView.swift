import SwiftUI

/// Search sheet — lets the user type an acronym (or prefix) and jump straight
/// to that card in the active deck.
///
/// Opened via the magnifying-glass button in the QuizView toolbar.
/// Dismisses automatically after the user taps an entry.
struct JumpToView: View {
    @EnvironmentObject private var store: QuizStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [(index: Int, item: Acronym)] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty {
            // Show the full list when nothing is typed yet.
            return store.activeItems.enumerated().map { ($0.offset, $0.element) }
        }
        return store.activeItems.enumerated().compactMap { offset, item in
            item.key.uppercased().hasPrefix(q) ? (offset, item) : nil
        }
    }

    var body: some View {
        NavigationStack {
            List(matches, id: \.item.id) { match in
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
            .listStyle(.plain)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Acronym")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .navigationTitle("Jump To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { searchFocused = true }
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

#Preview {
    JumpToView()
        .environmentObject(QuizStore())
}
