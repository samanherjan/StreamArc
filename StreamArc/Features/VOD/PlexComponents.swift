import StreamArcCore
import SwiftUI
import Kingfisher

// MARK: - PlexShelfSection
// A titled horizontal shelf section used across Movies, Series and Home screens.

struct PlexShelfSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Color.saTextPrimary)
                Spacer()
            }
            .padding(.horizontal)

            content()
        }
    }
}
