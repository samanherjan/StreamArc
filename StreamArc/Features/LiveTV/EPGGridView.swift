import StreamArcCore
import SwiftUI

// 2D EPG grid: channels on Y-axis, time slots on X-axis.
// Premium-only feature. Free users see "Now / Next" only.
struct EPGGridView: View {

    let channels: [Channel]
    let epgMap: [String: [EPGProgram]]
    var onChannelTap: (Channel) -> Void

    @Environment(EntitlementManager.self) private var entitlements
    @State private var showPaywall = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedProgram: EPGProgram?
    @State private var selectedProgramChannel: Channel?

    private let timeSlotWidth: CGFloat = 200
    private let rowHeight:     CGFloat = 56
    private let channelWidth:  CGFloat = 140
    // 48 half-hour slots = 24 hours
    private let totalSlots = 48

    var body: some View {
        if entitlements.isPremium {
            VStack(spacing: 0) {
                datePicker
                    .padding(.vertical, 8)
                    .background(Color.saBackground)
                fullGrid
            }
            .sheet(item: $selectedProgram) { prog in
                if let ch = selectedProgramChannel {
                    ProgramDetailSheet(
                        program: prog,
                        channel: ch,
                        onTuneIn: {
                            selectedProgram = nil
                            onChannelTap(ch)
                        }
                    )
                }
            }
        } else {
            nowNextGrid
                .overlay(alignment: .bottom) {
                    upgradeBar
                }
        }
    }

    // MARK: - Date Picker

    private var datePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))!
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : dayAbbrev(date))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.saTextSecondary)
                            Text(dayNumber(date))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected ? Color.white : Color.saTextPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.saAccent : Color.saCard.opacity(0.6))
                        )
                    }
                    .cardFocusable()
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Full EPG grid (premium)

    private var fullGrid: some View {
        ScrollViewReader { scrollProxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(channels) { channel in
                            HStack(spacing: 0) {
                                // Pinned channel label
                                Text(channel.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .frame(width: channelWidth, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .frame(height: rowHeight)
                                    .background(Color.saSurface)

                                // Program cells
                                ZStack(alignment: .leading) {
                                    // Background time-slot grid lines
                                    HStack(spacing: 0) {
                                        ForEach(0..<totalSlots, id: \.self) { _ in
                                            Divider()
                                                .background(Color.white.opacity(0.04))
                                                .frame(width: timeSlotWidth)
                                        }
                                    }

                                    HStack(spacing: 2) {
                                        let programs = epgMap[channel.epgId ?? channel.id] ?? []
                                        ForEach(programs.filter { isVisible($0) }) { program in
                                            programCell(program, for: channel)
                                        }
                                    }
                                }
                                .frame(height: rowHeight)
                            }
                            Divider().background(Color.saCard)
                        }
                    } header: {
                        timelineHeader
                    }
                }
            }
            .background(Color.saBackground)
            .onAppear {
                // Scroll to current time when viewing today
                if Calendar.current.isDateInToday(selectedDate) {
                    scrollProxy.scrollTo("currentTime", anchor: .leading)
                }
            }
            .onChange(of: selectedDate) { _, _ in
                if Calendar.current.isDateInToday(selectedDate) {
                    scrollProxy.scrollTo("currentTime", anchor: .leading)
                }
            }
        }
    }

    private func programCell(_ program: EPGProgram, for channel: Channel) -> some View {
        let duration = max(30, program.endDate.timeIntervalSince(program.startDate) / 60)
        let w = CGFloat(duration) * (timeSlotWidth / 30)
        let isNow = program.isCurrentlyAiring
        return Button {
            selectedProgram = program
            selectedProgramChannel = channel
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(program.title)
                    .font(.caption.bold())
                    .foregroundStyle(isNow ? .white : Color.saTextPrimary)
                    .lineLimit(1)
                Text(timeString(program.startDate))
                    .font(.caption2)
                    .foregroundStyle(isNow ? .white.opacity(0.8) : Color.saTextSecondary)

                // Progress bar for currently-airing programs
                if isNow {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.3)).frame(height: 2)
                            Capsule().fill(Color.white)
                                .frame(width: geo.size.width * program.progress, height: 2)
                        }
                    }
                    .frame(height: 2)
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: w - 2, height: rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isNow ? Color.saAccent : Color.saCard.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isNow ? Color.saAccent.opacity(0.5) : Color.white.opacity(0.04), lineWidth: 1)
            )
            // Dim past programs slightly
            .opacity(program.endDate < Date.now ? 0.5 : 1.0)
        }
        .cardFocusable()
#if os(tvOS)
        .buttonStyle(.card)
        .focusable()
#endif
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Color.saSurface.frame(width: channelWidth, height: 36)
            ForEach(Array(timeSlots.enumerated()), id: \.offset) { idx, date in
                ZStack(alignment: .leading) {
                    Text(timeString(date))
                        .font(.caption2)
                        .foregroundStyle(Color.saTextSecondary)
                        .padding(.leading, 8)

                    // "Now" indicator line
                    if Calendar.current.isDateInToday(selectedDate),
                       let nowOffset = nowXOffset(for: date, slotIndex: idx) {
                        Rectangle()
                            .fill(Color.saAccent)
                            .frame(width: 2)
                            .offset(x: nowOffset)
                            .id("currentTime")
                    }
                }
                .frame(width: timeSlotWidth * 2, height: 36, alignment: .leading)
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
                    // Progress
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.saSurface).frame(height: 3)
                            Capsule().fill(Color.saAccent)
                                .frame(width: geo.size.width * now.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
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
        .cardFocusable()
        .paywallSheet(isPresented: $showPaywall)
    }

    // MARK: - Helpers

    private var timeSlots: [Date] {
        var slots: [Date] = []
        let start = Calendar.current.startOfDay(for: selectedDate)
        for i in stride(from: 0, to: 24, by: 1) {
            slots.append(start.addingTimeInterval(Double(i) * 3600))
        }
        return slots
    }

    private var windowStart: Date { Calendar.current.startOfDay(for: selectedDate) }
    private var windowEnd: Date { windowStart.addingTimeInterval(86_400) }

    private func isVisible(_ program: EPGProgram) -> Bool {
        program.endDate > windowStart && program.startDate < windowEnd
    }

    /// X offset for the "now" red indicator within a specific 1-hour header slot.
    private func nowXOffset(for slotDate: Date, slotIndex: Int) -> CGFloat? {
        let now = Date.now
        let slotEnd = slotDate.addingTimeInterval(3600)
        guard now >= slotDate, now < slotEnd else { return nil }
        let fraction = now.timeIntervalSince(slotDate) / 3600
        return CGFloat(fraction) * timeSlotWidth * 2
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func timeString(_ date: Date) -> String { Self.timeFormatter.string(from: date) }

    private func dayAbbrev(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

// MARK: - Program Detail Sheet

private struct ProgramDetailSheet: View {
    let program: EPGProgram
    let channel: Channel
    var onTuneIn: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Channel + time
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.saAccent)
                            HStack(spacing: 8) {
                                Text(timeRange)
                                    .font(.caption)
                                    .foregroundStyle(Color.saTextSecondary)
                                if let cat = program.category {
                                    Text("·")
                                        .foregroundStyle(Color.saTextSecondary)
                                    Text(cat)
                                        .font(.caption)
                                        .foregroundStyle(Color.saTextSecondary)
                                }
                            }
                        }
                        Spacer()
                        if program.isCurrentlyAiring {
                            Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }

                    // Progress bar (if currently airing)
                    if program.isCurrentlyAiring {
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.saCard).frame(height: 6)
                                    Capsule().fill(Color.saAccent)
                                        .frame(width: geo.size.width * program.progress, height: 6)
                                }
                            }
                            .frame(height: 6)
                            HStack {
                                Text(timeString(program.startDate))
                                Spacer()
                                Text(timeString(program.endDate))
                            }
                            .font(.caption2)
                            .foregroundStyle(Color.saTextSecondary)
                        }
                    }

                    // Description
                    if let desc = program.description, !desc.isEmpty {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(Color.saTextPrimary)
                            .lineSpacing(4)
                    } else {
                        Text("No program description available.")
                            .font(.body)
                            .foregroundStyle(Color.saTextSecondary)
                            .italic()
                    }

                    // Tune in button
                    if program.isCurrentlyAiring || program.startDate > .now {
                        Button(action: onTuneIn) {
                            Label(
                                program.isCurrentlyAiring ? "Watch Now" : "Tune In",
                                systemImage: program.isCurrentlyAiring ? "play.fill" : "bell.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.saAccent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .background(Color.saBackground.ignoresSafeArea())
            .navigationTitle(program.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: program.startDate)) – \(f.string(from: program.endDate))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func timeString(_ date: Date) -> String { Self.timeFormatter.string(from: date) }
}
