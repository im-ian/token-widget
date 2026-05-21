import SwiftUI
import WidgetKit

struct TokenWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenUsageSnapshot
}

struct TokenWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenWidgetEntry {
        TokenWidgetEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenWidgetEntry) -> Void) {
        completion(TokenWidgetEntry(date: Date(), snapshot: TokenUsageStore().loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenWidgetEntry>) -> Void) {
        let entry = TokenWidgetEntry(date: Date(), snapshot: TokenUsageStore().loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct TokenStatusWidget: Widget {
    let kind = "TokenStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenWidgetProvider()) { entry in
            TokenStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Token Status")
        .description("Available Codex and Claude quota bars with one-minute refresh.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TokenWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.snapshot.metrics.isEmpty {
                emptyState
            } else {
                bars
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Token Status")
                    .font(.headline)
                Text("Last updated \(formatLastUpdatedTime(entry.snapshot.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.clockwise")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No data")
                .font(.subheadline.weight(.semibold))
            Text("Open Token Widget and refresh once.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            ForEach(TokenProvider.widgetDisplayOrder) { provider in
                HStack(spacing: family == .systemSmall ? 8 : 10) {
                    ForEach(UsageWindow.defaultDisplayWindows) { window in
                        TokenMetricBar(
                            metric: metric(provider: provider, window: window),
                            provider: provider,
                            window: window,
                            compact: family == .systemSmall
                        )
                    }
                }
            }
        }
    }

    private func metric(provider: TokenProvider, window: UsageWindow) -> TokenUsageMetric? {
        entry.snapshot.metrics.first { $0.provider == provider && $0.window == window }
    }
}

struct TokenMetricBar: View {
    let metric: TokenUsageMetric?
    let provider: TokenProvider
    let window: UsageWindow
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                Text(window.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metricValue)
                    .font(.caption.monospacedDigit())
            }

            if metric?.errorMessage == nil {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.18))
                        Capsule()
                            .fill(provider.primaryColor)
                            .frame(width: max(proxy.size.width * remainingFraction, 4))
                    }
                }
                .frame(height: compact ? 6 : 8)
            } else {
                Capsule()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: compact ? 6 : 8)
            }

            Text(resetText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricValue: String {
        guard let metric else { return "-" }
        if let remainingPercent = metric.remainingPercent {
            return formatPercent(remainingPercent)
        }

        guard metric.tokenLimit > 0 else { return "-" }
        return formatTokenCount(metric.remainingTokens)
    }

    private var remainingFraction: Double {
        metric?.remainingFraction ?? 0
    }

    private var resetText: String {
        guard let resetAt = metric?.resetAt else { return "Time left -" }
        return "Time left \(formatRemainingResetDuration(resetAt))"
    }
}

private extension TokenProvider {
    static let widgetDisplayOrder: [TokenProvider] = [.codex, .claude]

    var primaryColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.06, green: 0.72, blue: 0.46)
        case .claude:
            return Color(red: 0.84, green: 0.36, blue: 0.18)
        }
    }
}

private let previewSnapshot = TokenUsageSnapshot(
    metrics: [
        TokenUsageMetric(provider: .codex, window: .fiveHours, usedTokens: 0, tokenLimit: 0, usedPercent: 28, resetAt: Date().addingTimeInterval(3600), updatedAt: Date(), sourceDescription: "Preview"),
        TokenUsageMetric(provider: .codex, window: .weekly, usedTokens: 0, tokenLimit: 0, usedPercent: 40, resetAt: Date().addingTimeInterval(86_400), updatedAt: Date(), sourceDescription: "Preview"),
        TokenUsageMetric(provider: .claude, window: .fiveHours, usedTokens: 0, tokenLimit: 0, usedPercent: 51, resetAt: Date().addingTimeInterval(1800), updatedAt: Date(), sourceDescription: "Preview"),
        TokenUsageMetric(provider: .claude, window: .weekly, usedTokens: 0, tokenLimit: 0, usedPercent: 62, resetAt: Date().addingTimeInterval(172_800), updatedAt: Date(), sourceDescription: "Preview")
    ],
    updatedAt: Date()
)
