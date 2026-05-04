// PlexComponents.swift
// All shared Plex-style UI components live in MoviesView.swift,
// which is included in all build targets.

import StreamArcCore
import SwiftUI
import Kingfisher

// MARK: - PlexShelfSection
// A titled horizontal shelf section used across Movies, Series and Home screens.

struct PlexShelfSection<Content: View>: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = Color.saAccent
    var badge: String? = nil
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        #if os(tvOS)
                        .font(.title3.bold())
                        #else
                        .font(.subheadline.bold())
                        #endif
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    #if os(tvOS)
                    .font(.title2.bold())
                    #else
                    .font(.title3.bold())
                    #endif
                    .foregroundStyle(Color.saTextPrimary)
                if let badge {
                    Text(badge).font(.caption2.bold()).foregroundStyle(Color.saTextSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.saCard).clipShape(Capsule())
                }
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text("See All").font(.caption.bold()).foregroundStyle(Color.saAccent)
                            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(Color.saAccent.opacity(0.75))
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            content()
        }
    }
}

// MARK: - Genre Tag

struct GenreTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.bold())
            .foregroundStyle(Color.saTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.saCard)
            .clipShape(Capsule())
    }
}
