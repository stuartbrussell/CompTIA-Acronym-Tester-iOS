import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        if let icon = appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(radius: 3)
                        }
                        VStack(spacing: 4) {
                            Text("CompTIA Acronym Tester")
                                .font(.title3.weight(.semibold))
                            Text(version)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Cards") {
                    row("hand.tap",           "Tap",         "Reveal or hide the full expansion")
                    row("arrow.left",         "Swipe left",  "Go to the next card")
                    row("arrow.right",        "Swipe right", "Go to the previous card")
                    row("hand.point.up.left", "Long-press",  "Reset the card to untested")
                }

                Section("Marking") {
                    row("checkmark.circle.fill", "Correct",   "Mark the current card correct")
                    row("xmark.circle.fill",     "Incorrect", "Mark the current card incorrect")
                    row("line.3.horizontal.decrease.circle", "Filter",
                        "Limit navigation to All, Untested, or Incorrect cards. Switches back to All automatically when the filtered set is empty.")
                }

                Section("Browsing & Search") {
                    row("globe",          "Wikipedia", "Opens the Wikipedia article for the current acronym in a browser sheet")
                    row("magnifyingglass", "Jump To",  "Tap the search button (top right) to jump directly to any acronym by name")
                }

                Section("Settings") {
                    row("list.bullet",            "Lists",           "Enable or disable the A+, Network+, and Network Ports acronym sets")
                    row("checkmark.seal",          "Strict mode",     "Show only acronyms that appear in the official CompTIA exam objectives")
                    row("textformat.size",         "Acronym length",  "Filter to a specific character count to drill on longer acronyms")
                    row("clock.arrow.circlepath",  "Session restore", "Saves progress when you leave the app and resumes where you left off on relaunch")
                }

                Section {
                    Text("© 2026 Stuart B. Russell")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ icon: String, _ label: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return nil }
        return UIImage(named: name)
    }
}

#Preview {
    AboutView()
}
