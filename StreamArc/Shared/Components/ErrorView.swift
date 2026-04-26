import SwiftUI

struct ErrorView: View {
    var message: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.saError)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.saTextSecondary)
                .padding(.horizontal, 32)

            if let retry = retryAction {
                Button("Retry", action: retry)
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .streamArcBackground()
    }
}

struct EmptyContentView: View {
    var title: String = "No Content Found"
    var subtitle: String = "Check your source settings and try again."
    var systemImage: String = "antenna.radiowaves.left.and.right.slash"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(Color.saTextSecondary)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.saTextPrimary)
            Text(subtitle)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.saTextSecondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Button styles

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Color.saAccent.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(Color.saAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.saAccent.opacity(0.15))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
