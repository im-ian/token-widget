import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var viewModel = TokenDashboardViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(TokenProvider.allCases) { provider in
                    GridRow {
                        providerLabel(provider)

                        ForEach(UsageWindow.defaultDisplayWindows) { window in
                            metricCell(provider: provider, window: window)
                        }
                    }
                }
            }

            Divider()

            footer
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 320)
        .task {
            await viewModel.load()
            await viewModel.runAutoRefreshLoop()
        }
        .onOpenURL { url in
            guard url.scheme == "tokenwidget" else { return }
            Task { await viewModel.refresh() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Token Widget")
                    .font(.title2.weight(.semibold))
                Text("Available quota for 5h and weekly windows")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRefreshing)
        }
    }

    private func providerLabel(_ provider: TokenProvider) -> some View {
        Text(provider.displayName)
            .font(.headline)
            .frame(width: 72, alignment: .leading)
    }

    private func metricCell(provider: TokenProvider, window: UsageWindow) -> some View {
        let metric = viewModel.metric(provider: provider, window: window)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(metric.map { metricValue($0) } ?? "-")
                    .font(.subheadline.monospacedDigit())
            }

            ProgressView(value: metric?.remainingFraction ?? 0)
                .tint(color(for: metric))

            Text(metricDescription(metric))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: 190, height: 104)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Text("Last updated \(formatLastUpdatedTime(viewModel.snapshot.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Bars show available quota. Codex uses ~/.codex/sessions rate_limits. Claude uses the latest captured statusline rate_limits from ~/.claude/token-widget/claude-rate-limits.json.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func metricDescription(_ metric: TokenUsageMetric?) -> String {
        guard let metric else { return "No snapshot yet" }
        if let errorMessage = metric.errorMessage {
            return errorMessage
        }

        var parts: [String] = []

        if let remainingPercent = metric.remainingPercent {
            parts.append("\(formatPercent(remainingPercent)) available")
        } else if metric.tokenLimit > 0 {
            parts.append("\(formatTokenCount(metric.remainingTokens)) available")
        } else {
            parts.append("No rate-limit data")
        }

        if let resetAt = metric.resetAt {
            parts.append("resets at \(formatResetTime(resetAt))")
        }

        return parts.joined(separator: ", ")
    }

    private func metricValue(_ metric: TokenUsageMetric) -> String {
        if let remainingPercent = metric.remainingPercent {
            return formatPercent(remainingPercent)
        }

        guard metric.tokenLimit > 0 else { return "-" }
        return formatTokenCount(metric.remainingTokens)
    }

    private func color(for metric: TokenUsageMetric?) -> Color {
        guard let fraction = metric?.remainingFraction else { return .secondary }
        switch fraction {
        case 0..<0.2:
            return .red
        case 0.2..<0.45:
            return .orange
        default:
            return .green
        }
    }
}

@Observable
@MainActor
final class TokenDashboardViewModel {
    private let store = TokenUsageStore()
    private let refreshService = TokenUsageRefreshService()

    var snapshot: TokenUsageSnapshot = .empty
    var preferences: TokenUsagePreferences = .defaults
    var isRefreshing = false
    var errorMessage: String?

    func load() async {
        preferences = store.loadPreferences()
        snapshot = store.loadSnapshot()
        if snapshot.metrics.isEmpty {
            await refresh()
        }
    }

    func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        store.savePreferences(preferences)
        let newSnapshot = await refreshService.refresh(preferences: preferences)
        snapshot = newSnapshot
        store.saveSnapshot(newSnapshot)
        WidgetCenter.shared.reloadAllTimelines()

        if newSnapshot.metrics.allSatisfy({ $0.errorMessage != nil }) {
            errorMessage = "Could not read local rate-limit data. Check Full Disk Access if this app is sandboxed."
        }
    }

    func runAutoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func metric(provider: TokenProvider, window: UsageWindow) -> TokenUsageMetric? {
        snapshot.metrics.first { $0.provider == provider && $0.window == window }
    }
}
