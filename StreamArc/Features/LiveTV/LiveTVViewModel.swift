import Foundation

@MainActor
@Observable
final class LiveTVViewModel {

    var searchText = ""
    var selectedCountry: String?   // e.g. "NO", "UK", "4K"
    var selectedGroup: String?     // original full group title
    var selectedChannel: Channel?

    private let freeTierChannelCap = 200

    // MARK: - Two-level hierarchy

    struct CountryGroup: Identifiable {
        let id: String          // country code or prefix
        let displayName: String // "Norway", "United Kingdom"
        let flag: String        // 🇳🇴 or SF Symbol fallback
        let categories: [CategoryGroup]
        var totalChannels: Int { categories.reduce(0) { $0 + $1.channels.count } }
    }

    struct CategoryGroup: Identifiable {
        let id: String          // original full group title
        let cleanName: String   // e.g. "HD/RAW", "VIP", "BBC IPLAYER"
        let channels: [Channel]
    }

    /// Builds the two-level country → category hierarchy
    func countryGroups(from channels: [Channel], isPremium: Bool) -> [CountryGroup] {
        let capped = cappedChannels(from: channels, isPremium: isPremium)

        // Parse into: [countryCode: [originalGroupTitle: [Channel]]]
        var countryOrder: [String] = []
        var catDict: [String: [String: [Channel]]] = [:]
        var catOrder: [String: [String]] = [:]

        for ch in capped {
            let group = ch.groupTitle.isEmpty ? "General" : ch.groupTitle
            let (code, clean) = Self.parseCountryCode(from: group)

            if catDict[code] == nil {
                countryOrder.append(code)
                catDict[code] = [:]
                catOrder[code] = []
            }
            if catDict[code]![group] == nil {
                catOrder[code]!.append(group)
            }
            catDict[code]![group, default: []].append(ch)
            _ = clean // used below
        }

        return countryOrder.map { code in
            let cats = (catOrder[code] ?? []).map { groupTitle -> CategoryGroup in
                let (_, clean) = Self.parseCountryCode(from: groupTitle)
                return CategoryGroup(
                    id: groupTitle,
                    cleanName: clean,
                    channels: catDict[code]![groupTitle] ?? []
                )
            }
            return CountryGroup(
                id: code,
                displayName: Self.countryDisplayName(for: code),
                flag: Self.flagEmoji(for: code),
                categories: cats
            )
        }
    }

    /// Country codes for the pill bar
    func countryCodes(from channels: [Channel], isPremium: Bool) -> [String] {
        let capped = cappedChannels(from: channels, isPremium: isPremium)
        var seen = Set<String>()
        var result: [String] = []
        for ch in capped {
            let group = ch.groupTitle.isEmpty ? "General" : ch.groupTitle
            let (code, _) = Self.parseCountryCode(from: group)
            if seen.insert(code).inserted {
                result.append(code)
            }
        }
        return result
    }

    /// Categories within a selected country
    func categoriesForCountry(_ code: String, from channels: [Channel], isPremium: Bool) -> [CategoryGroup] {
        countryGroups(from: channels, isPremium: isPremium)
            .first(where: { $0.id == code })?.categories ?? []
    }

    /// Navigate back one level
    func goBack() {
        if selectedGroup != nil {
            selectedGroup = nil
        } else if selectedCountry != nil {
            selectedCountry = nil
        }
    }

    // MARK: - Existing functionality

    private func cappedChannels(from channels: [Channel], isPremium: Bool) -> [Channel] {
        isPremium ? channels : Array(channels.prefix(freeTierChannelCap))
    }

    func allCappedChannels(from channels: [Channel], isPremium: Bool) -> [Channel] {
        cappedChannels(from: channels, isPremium: isPremium)
    }

    func filteredChannels(from channels: [Channel], isPremium: Bool) -> [Channel] {
        let capped = cappedChannels(from: channels, isPremium: isPremium)
        if !searchText.isEmpty {
            return capped.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if let group = selectedGroup {
            return capped.filter { $0.groupTitle == group }
        }
        return capped
    }

    func groups(from channels: [Channel], isPremium: Bool) -> [String] {
        let capped = cappedChannels(from: channels, isPremium: isPremium)
        let groups = capped.compactMap { $0.groupTitle.isEmpty ? nil : $0.groupTitle }
        return Array(Set(groups)).sorted()
    }

    var isAtFreeCap: Bool = false

    func checkFreeCap(channels: [Channel], isPremium: Bool) {
        isAtFreeCap = !isPremium && channels.count > freeTierChannelCap
    }

    // MARK: - Parsing helpers

    /// Splits "NO| NORWAY HD/RAW" → ("NO", "NORWAY HD/RAW")
    /// Splits "4K| UHD 3840P" → ("4K", "UHD 3840P")
    /// "General" → ("OTHER", "General")
    static func parseCountryCode(from groupTitle: String) -> (code: String, cleanName: String) {
        if let pipeRange = groupTitle.range(of: "| ") ?? groupTitle.range(of: "|") {
            let code = String(groupTitle[..<pipeRange.lowerBound]).trimmingCharacters(in: .whitespaces).uppercased()
            let name = String(groupTitle[pipeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !code.isEmpty {
                return (code, name.isEmpty ? code : name)
            }
        }
        return ("OTHER", groupTitle)
    }

    /// Returns flag emoji for a 2-letter country code, or a symbol for special codes
    static func flagEmoji(for code: String) -> String {
        // Map common non-ISO codes to their ISO equivalents
        let isoMap: [String: String] = [
            "UK": "GB",
            "EN": "GB",
            "KO": "KR",
            "JA": "JP",
            "EL": "GR",
            "DA": "DK",
            "SV": "SE",
            "HI": "IN",
            "FA": "IR",
            "HE": "IL",
            "AR": "SA",
            "ZH": "CN",
            "CS": "CZ",
            "SL": "SI",
            "ET": "EE",
            "VI": "VN",
            "MS": "MY",
            "TL": "PH",
        ]
        let mapped = isoMap[code.uppercased()] ?? code.uppercased()

        // Try as ISO country code (2 letters)
        if mapped.count == 2 && mapped.allSatisfy({ $0.isLetter }) {
            let base: UInt32 = 127397
            let emoji = mapped.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
                .map { String($0) }.joined()
            if !emoji.isEmpty { return emoji }
        }
        // Special prefixes
        switch code {
        case "4K":    return "4\u{FE0F}\u{20E3}"
        case "8K":    return "8\u{FE0F}\u{20E3}"
        case "OTHER": return "\u{1F4FA}"
        default:      return "\u{1F4E1}"
        }
    }

    /// Returns a human-readable country name
    static func countryDisplayName(for code: String) -> String {
        // Manual overrides for common non-ISO or preferred names
        let nameOverrides: [String: String] = [
            "UK": "United Kingdom",
            "US": "United States",
            "OTHER": "Other",
            "4K": "4K Ultra HD",
            "8K": "8K Ultra HD",
        ]
        if let name = nameOverrides[code.uppercased()] { return name }

        if let name = Locale.current.localizedString(forRegionCode: code), !name.isEmpty {
            return name
        }
        return code
    }
}
