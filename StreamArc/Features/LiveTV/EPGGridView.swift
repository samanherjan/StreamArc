import SwiftUI

// 2D EPG grid: channels on Y-axis, time slots on X-axis.
// Premium-only feature. Free users see "Now / Next" only.
struct EPGGridView: View {

    let channels: [Channel]
    let epgMap: [String: [EPGProgram]]
    var onChannelTap: (Channel) -> Void

    @Environment(EntitlementManager.self) private var entitlements
    @State private var showPaywall = false

    private let timeSlotWidth: CGFloat = 200
    private let rowHeight:     CGFloat = 56
    private let channelWidth:  CGFloat = 140
    private let hoursVisible   = 4

    var body: some View {
        if entitlements.isPremium {
            fullGrid
        } else {
            nowNextGrid
                .overlay(alignment: .bottom) {
                    upgradeBar
                }
        }
    }

    // MARK: - Full EPG grid (premium)

    private var fullGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(channels) { channel in
                        HStack(spacing: 0) {
                            // Channel label
                            Text(channel.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .frame(width: channelWidth, alignment: .leading)
                                .padding(.horizontal, 8)
                                .frame(height: rowHeight)
                                .background(Color.saSurface)

                            // Programs
                            HStack(spacing: 2) {
                                let programs = epgMap[channel.epgId ?? channel.id] ?? []
                                ForEach(programs.filter { isVisible($0) }) { program in
                                    programCell(program, for: channel)
                                }
                            }
                        }
                        Divider().background(Color.saCard)
                    }
                } header: {
                    timelineHeader
                }
            }
        }
        .background(Color.saBackground)
    }

    private func programCell(_ program: EPGProgram, for channel: Channel) -> some View {
        let w = max(60, CGFloat(program.endDate.timeIntervalSince(program.startDate)) / 60 * (timeSlotWidth / 30))
        return Button {
            onChannelTap(channel)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(timeString(program.startDate))
                    .font(.caption2)
                    .foregroundStyle(Color.saTextSecondary)
            }
            .padding(.horizontal, 8)
            .frame(width: w, height: rowHeight, alignment: .leading)
            .background(program.isCurrentlyAiring ? Color.saAccent.opacity(0.25) : Color.saCard)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
#if os(tvOS)
        .buttonStyle(.card)
        .focusable()
#endif
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Color.saSurface.frame(width: channelWidth, height: 32)
            ForEach(timeSlots, id: \.self) { date in
                Text(timeString(date))
                    .font(.caption2)
                    .foregroundStyle(Color.saTextSecondary)
                    .frame(width: timeSlotWidth * 2, height: 32, alignment: .leading)
                    .padding(.leading, 8)
                    .background(Color.saBackground)
            }
        }
    }

    // MARK: - Now/Next grid (free)

    private var nowNextGrid: some View {
        List(channels) { channel in
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name).font(.headline).foregroundStyle(Color.saTextPrimary)
                if let now = channel.currentProgram {
                    Text("▶ \(now.title)").font(.caption).foregroundStyle(Color.saAccent)
                }
                if let next = channel.nextProgram {
                    Text("Next: \(next.title)").font(.caption2).foregroundStyle(Color.saTextSecondary)
                }
            }
            .onTapGesture { onChannelTap(channel) }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .background(Color.saBackground)
    }

    private var upgradeBar: some View {
        Button { showPaywall = true } label: {
            HStack {
                Image(systemName: "lock.fill")
                Text("Full 7-day EPG grid — StreamArc+")
                    .font(.subheadline.bold())
                Spacer()
                Text("Upgrade")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.saAccent)
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)
            .padding()
            .background(Color.saSurface)
        }
        .buttonStyle(.plain)
        .paywallSheet(isPresented: $showPaywall)
    }

    // MARK: - Helpers

    private var timeSlots: [Date] {
        var slots: [Date] = []
        let now = Calendar.current.date(bySetting: .minute, value: 0, of: Date.now)!
        for i in 0..<(hoursVisible * 2) {
            slots.append(now.addingTimeInterval(Double(i) * 1800))
        }
        return slots
    }

    private func isVisible(_ program: EPGProgram) -> Bool {
        let end = timeSlots.last ?? Date.now.addingTimeInterval(3600 * Double(hoursVisible))
        return program.endDate > (timeSlots.first ?? Date.now) && program.startDate < end
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
