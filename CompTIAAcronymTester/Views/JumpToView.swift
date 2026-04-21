import SwiftUI

/// Search sheet — lets the user type an acronym (or prefix) and jump straight
/// to that card in the active deck.
///
/// Opened via the magnifying-glass button in the QuizView toolbar.
/// Dismisses automatically after the user taps an entry.
///
/// Uses a plain TextField (rather than .searchable) so that @FocusState can
/// programmatically raise the keyboard the moment the sheet opens.
struct JumpToView: View {
    @EnvironmentObject private var store: QuizStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [(index: Int, item: Acronym)] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        if q.isEmpty {
            return store.activeItems.enumerated().map { ($0.offset, $0.element) }
        }
        return store.activeItems.enumerated().compactMap { offset, item in
            item.key.uppercased().hasPrefix(q) ? (offset, item) : nil
        }
    }

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
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                } else {
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
}

#Preview {
    JumpToView()
        .environmentObject(QuizStore())
}
