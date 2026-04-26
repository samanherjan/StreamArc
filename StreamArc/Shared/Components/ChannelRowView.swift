import SwiftUI
import Kingfisher

struct ChannelRowView: View {
    let channel: Channel
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Channel logo
            Group {
                if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundStyle(Color.saAccent)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.saSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Name + EPG
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.saAccent : Color.saTextPrimary)
                    .lineLimit(1)

                if let now = channel.currentProgram {
                    HStack(spacing: 4) {
                        Text(now.title)
                            .font(.caption)
                            .foregroundStyle(Color.saTextSecondary)
                            .lineLimit(1)
                        if let next = channel.nextProgram {
                            Text("·")
                                .foregroundStyle(Color.saTextSecondary)
                                .font(.caption)
                            Text(next.title)
                                .font(.caption)
                                .foregroundStyle(Color.saTextSecondary.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(channel.groupTitle.isEmpty ? "Live" : channel.groupTitle)
                        .font(.caption)
                        .foregroundStyle(Color.saTextSecondary)
                }
            }

            Spacer(minLength: 0)

            // Progress bar for current program
            if let program = channel.currentProgram {
                VStack(alignment: .trailing, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.saSurface)
                        .frame(width: 48, height: 4)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.saAccent)
                                .frame(width: 48 * program.progress)
                        }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.saAccent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }
}
