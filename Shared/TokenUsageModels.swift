import Foundation

enum TokenProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }
}

enum UsageWindow: String, Codable, CaseIterable, Identifiable {
    case fiveHours
    case weekly
    case monthly

    var id: String { rawValue }

    static let defaultDisplayWindows: [UsageWindow] = [.fiveHours, .weekly]

    var displayName: String {
        switch self {
        case .fiveHours:
            return "5h"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }

    var sortOrder: Int {
        switch self {
        case .fiveHours:
            return 0
        case .weekly:
            return 1
        case .monthly:
            return 2
        }
    }

    var duration: TimeInterval {
        switch self {
        case .fiveHours:
            return 5 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .monthly:
            return 30 * 24 * 60 * 60
        }
    }
}

struct TokenUsageMetric: Codable, Identifiable, Equatable {
    var provider: TokenProvider
    var window: UsageWindow
    var usedTokens: Int
    var tokenLimit: Int
    var usedPercent: Double?
    var resetAt: Date?
    var updatedAt: Date
    var sourceDescription: String
    var errorMessage: String?

    var id: String { "\(provider.rawValue)-\(window.rawValue)" }
    var remainingTokens: Int { max(tokenLimit - usedTokens, 0) }
    var usedFraction: Double {
        if let usedPercent {
            return min(max(usedPercent / 100, 0), 1)
        }

        guard tokenLimit > 0 else { return 0 }
        return min(Double(usedTokens) / Double(tokenLimit), 1)
    }
    var remainingFraction: Double {
        return max(1 - usedFraction, 0)
    }
    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return max(100 - min(max(usedPercent, 0), 100), 0)
    }
}

struct TokenUsageSnapshot: Codable, Equatable {
    var metrics: [TokenUsageMetric]
    var updatedAt: Date

    static let empty = TokenUsageSnapshot(metrics: [], updatedAt: .distantPast)
}

struct TokenUsagePreferences: Codable, Equatable {
    var limits: [String: Int]
    var enabledProviders: Set<TokenProvider>
    var enabledWindows: Set<UsageWindow>

    static let defaults = TokenUsagePreferences(
        limits: [:],
        enabledProviders: Set(TokenProvider.allCases),
        enabledWindows: Set(UsageWindow.defaultDisplayWindows)
    )

    func limit(provider: TokenProvider, window: UsageWindow) -> Int {
        limits[Self.key(provider: provider, window: window)] ?? 0
    }

    static func key(provider: TokenProvider, window: UsageWindow) -> String {
        "\(provider.rawValue).\(window.rawValue)"
    }
}

func formatTokenCount(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }

    if value >= 1_000 {
        return String(format: "%.0fK", Double(value) / 1_000)
    }

    return "\(value)"
}

func formatPercent(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))%"
    }

    return String(format: "%.1f%%", value)
}

func relativeDate(_ date: Date) -> String {
    guard date > .distantPast else { return "never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

func formatResetTime(_ date: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
    return formatter.string(from: date)
}

func formatLastUpdatedTime(_ date: Date) -> String {
    guard date > .distantPast else { return "-" }
    return formatResetTime(date)
}

func formatRemainingResetDuration(_ date: Date) -> String {
    let totalMinutes = max(Int(date.timeIntervalSince(Date()) / 60), 0)
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
        return "\(days)d \(hours)h \(minutes)m"
    }

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }

    return "\(minutes)m"
}
