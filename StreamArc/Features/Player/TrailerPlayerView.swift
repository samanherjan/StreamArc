import SwiftUI

struct TrailerPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
#if os(tvOS)
            // tvOS: play via AVPlayer (YouTube direct won't work, but this handles fallback)
            Text("Open YouTube for trailer")
                .foregroundStyle(Color.saTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.saBackground)
#else
            SafariWebView(url: url)
                .ignoresSafeArea()
#endif
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - SafariViewController wrapper (iOS/macOS)

#if !os(tvOS)
import SafariServices

struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
