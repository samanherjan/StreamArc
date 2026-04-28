import SwiftUI

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : Color.saTextSecondary)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(Color.saAccent)
                        } else {
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                )
                .contentShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}
