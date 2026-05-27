import SwiftUI

/// Main quiz screen.
///
/// Interaction model (iOS adaptation of the Python app's keyboard shortcuts):
///   - Tap the card           → toggle the expansion (was: space / return)
///   - Swipe left on card     → next item                (was: → / ↓)
///   - Swipe right on card    → previous item            (was: ← / ↑)
///   - Long-press the card    → reset result to untested (was: esc)
///   - Correct / Incorrect pill buttons mark the current item explicitly
///   - Segmented filter (All / Untested / Incorrect) limits navigation scope
///   - Browse button opens Wikipedia in an in-app Safari sheet
struct QuizView: View {
    @EnvironmentObject private var store: QuizStore
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var showingSettings = false
    @State private var showingJumpTo = false
    @State private var showingAbout = false
    @State private var safariURL: IdentifiedURL?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Acronym Tester")
                .navigationBarTitleDisplayMode(.inline)
                .background(appBackground.ignoresSafeArea())
                .toolbarBackground(Color(red: 0.93, green: 0.94, blue: 0.98), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAbout = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .accessibilityLabel("About")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 4) {
                            Button {
                                showingJumpTo = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .accessibilityLabel("Jump to acronym")
                            }
                            .disabled(store.activeItems.isEmpty)

                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .accessibilityLabel("Settings")
                            }
                        }
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingJumpTo) {
            JumpToView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .fullScreenCover(item: $safariURL) { identified in
            SafariView(url: identified.url)
                .ignoresSafeArea()
        }
        .alert("Acronym Lists Updated", isPresented: $updateManager.updateReady) {
            Button("Update Now") {
                updateManager.applyPendingUpdate()
            }
            Button("Later", role: .cancel) {
                updateManager.dismissUpdate()
            }
            Button("Skip This Version", role: .destructive) {
                updateManager.skipUpdate()
            }
        } message: {
            Text(updateManager.updateDescription)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.activeItems.isEmpty {
            emptyState
        } else {
            VStack(spacing: 24) {
                progressAndScore
                Spacer(minLength: 0)
                card
                Spacer(minLength: 0)
                correctnessControls
                navigationAndBrowse
                filterPicker
            }
            .padding()
        }
    }

    // MARK: - Header

    private var progressAndScore: some View {
        HStack {
            Text("\(store.currentIndex + 1) / \(store.activeItems.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("Correct \(store.correctCount)  ·  Incorrect \(store.incorrectCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Card

    private var card: some View {
        let item = store.currentItem
        return VStack(spacing: 20) {
            Text(item?.key ?? "")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .accessibilityLabel("Acronym: \(item?.key ?? "")")

            if store.revealed {
                Text(item?.joinedValue ?? "")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else {
                Text("Tap to reveal")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(resultColor.opacity(0.35), lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.toggleReveal()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            store.resetCurrentResult()
        }
        .gesture(swipeGesture)
        .animation(.default, value: store.currentIndex)
    }

    private var appBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.94, blue: 0.98),
                Color(red: 0.97, green: 0.97, blue: 0.99)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var resultColor: Color {
        switch store.currentResult() {
        case .correct:   return .green
        case .incorrect: return .red
        case .untested:  return .gray
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -40 {
                    store.next()
                } else if value.translation.width > 40 {
                    store.previous()
                }
            }
    }

    // MARK: - Correctness controls

    private var correctnessControls: some View {
        HStack(spacing: 12) {
            correctnessButton(
                title: "Incorrect",
                systemImage: "xmark.circle.fill",
                tint: .red,
                isSelected: store.currentResult() == .incorrect
            ) {
                store.mark(.incorrect)
            }
            correctnessButton(
                title: "Correct",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                isSelected: store.currentResult() == .correct
            ) {
                store.mark(.correct)
            }
        }
    }

    private func correctnessButton(title: String,
                                   systemImage: String,
                                   tint: Color,
                                   isSelected: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? tint : .secondary.opacity(0.4))
        .foregroundStyle(isSelected ? .white : .primary)
    }

    // MARK: - Nav row: prev / browse / next

    private var navigationAndBrowse: some View {
        HStack(spacing: 12) {
            navButton(systemImage: "chevron.left") { store.previous() }
            Button {
                openBrowse()
            } label: {
                Image("Wikipedia")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            }
            .buttonStyle(.plain)
            .disabled((store.currentItem?.urls.first) == nil)
            .opacity((store.currentItem?.urls.first) == nil ? 0.3 : 1)
            navButton(systemImage: "chevron.right") { store.next() }
        }
    }

    // MARK: - Filter

    private var filterPicker: some View {
        Picker("Filter", selection: $store.filterMode) {
            Text("All").tag(QuizStore.FilterMode.all)
            Text("Untested").tag(QuizStore.FilterMode.untested)
            Text("Incorrect").tag(QuizStore.FilterMode.incorrect)
        }
        .pickerStyle(.segmented)
    }

    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 80, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    /// Opens the first URL inline in a Safari sheet. If the acronym has
    /// multiple meanings, the additional URLs are opened in the system
    /// browser via `UIApplication.open`.
    private func openBrowse() {
        guard let item = store.currentItem else { return }
        let urls = item.urls
        guard let first = urls.first else { return }
        safariURL = IdentifiedURL(url: first)
        for extra in urls.dropFirst() {
            UIApplication.shared.open(extra)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No acronyms loaded")
                .font(.title3.weight(.semibold))
            Text("Open Settings and enable at least one list, or relax the length filter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                showingSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// Wraps a URL so it can drive `.sheet(item:)`.
struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview {
    QuizView()
        .environmentObject(QuizStore())
        .environmentObject(UpdateManager())
}
