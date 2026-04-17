import SwiftUI
import SafariServices

/// Wraps `SFSafariViewController` so a Wikipedia article renders inside the
/// app instead of kicking the user out to Safari.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor.label
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController,
                                context: Context) {
        // Nothing to update — SFSafariViewController owns its own navigation.
    }
}
