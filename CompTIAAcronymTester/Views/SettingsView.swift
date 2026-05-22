import SwiftUI

/// Mirrors the Python app's debug window and the length-filter dropdown.
struct SettingsView: View {
    @EnvironmentObject private var store: QuizStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                listsSection
                filtersSection
                sessionSection
                resetSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Lists

    private var listsSection: some View {
        Section {
            ForEach(AcronymList.all) { list in
                Toggle(list.displayName,
                       isOn: binding(for: list))
            }
        } header: {
            Text("Lists")
        } footer: {
            Text("Enabled lists are combined into a single shuffled deck. Duplicate acronyms with different meanings are shown stacked.")
        }
    }

    private func binding(for list: AcronymList) -> Binding<Bool> {
        Binding(
            get: { store.enabledListIDs.contains(list.id) },
            set: { newValue in
                var updated = store.enabledListIDs
                if newValue { updated.insert(list.id) } else { updated.remove(list.id) }
                store.enabledListIDs = updated
            }
        )
    }

    // MARK: - Filters

    private var filtersSection: some View {
        Section {
            Toggle("Strict (CompTIA objectives only)", isOn: $store.strictMode)

            Picker("Acronym length", selection: $store.lengthFilter) {
                ForEach(store.availableLengths, id: \.self) { length in
                    Text(lengthLabel(length)).tag(length)
                }
            }
        } header: {
            Text("Filters")
        } footer: {
            Text("Strict mode hides extra acronyms that aren't part of the official exam objectives. Use the length picker to drill on longer acronyms.")
        }
    }

    private func lengthLabel(_ n: Int) -> String {
        n == 0 ? "All lengths" : "\(n) characters"
    }

    // MARK: - Session restore

    private var sessionSection: some View {
        Section {
            Toggle("Resume where I left off", isOn: $store.sessionRestoreEnabled)
        } header: {
            Text("Session")
        } footer: {
            Text("Saves your progress when you leave the app. On relaunch, acronyms you've already tested stay behind you and untested ones are ahead, freshly shuffled.")
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button {
                store.reshuffleAndReset()
            } label: {
                Label("Reshuffle & Reset Score", systemImage: "shuffle")
            }
            Button(role: .destructive) {
                store.resetScore()
            } label: {
                Label("Reset Score Only", systemImage: "arrow.counterclockwise")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Active items", value: "\(store.activeItems.count)")
            LabeledContent("Total acronyms", value: "\(store.allItems.count)")
        } header: {
            Text("Current session")
        }
    }

    // MARK: - Debug

#if DEBUG
    private var debugSection: some View {
        Section {
            Button {
                store.printDuplicates()
            } label: {
                Label("Print Duplicates to Console", systemImage: "doc.text.magnifyingglass")
            }
            #if targetEnvironment(simulator)
            Button {
                openDocumentsInFinder()
            } label: {
                Label("Copy Documents Path", systemImage: "doc.on.clipboard")
            }
            #endif
        } header: {
            Text("Debug")
        } footer: {
            Text("Loads all rows from selected lists and prints entries that share a key (case-insensitive) to the Xcode console.")
        }
    }

    #if targetEnvironment(simulator)
    private func openDocumentsInFinder() {
        let path = URL.documentsDirectory.path(percentEncoded: false)
        UIPasteboard.general.string = path
        print("Documents path (copied to clipboard): \(path)")
    }
    #endif
#endif
}

#Preview {
    SettingsView()
        .environmentObject(QuizStore())
}
