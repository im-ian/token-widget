import Foundation

struct TokenUsageRefreshService {
    func refresh(preferences: TokenUsagePreferences) async -> TokenUsageSnapshot {
        let now = Date()
        let codexRateLimits = CodexRateLimitReader().readRateLimits()
        let claudeRateLimits = ClaudeRateLimitReader().readRateLimits()
        let enabledWindows = UsageWindow.defaultDisplayWindows.filter { preferences.enabledWindows.contains($0) }
        let enabledProviders = preferences.enabledProviders.sorted { $0.rawValue < $1.rawValue }

        let metrics = enabledProviders.flatMap { provider in
            enabledWindows.map { window in
                metric(
                    provider: provider,
                    window: window,
                    codexRateLimits: codexRateLimits,
                    claudeRateLimits: claudeRateLimits,
                    now: now
                )
            }
        }

        return TokenUsageSnapshot(metrics: metrics, updatedAt: now)
    }

    private func metric(
        provider: TokenProvider,
        window: UsageWindow,
        codexRateLimits: [UsageWindow: RateLimitWindow],
        claudeRateLimits: [UsageWindow: RateLimitWindow],
        now: Date
    ) -> TokenUsageMetric {
        if provider == .codex, let rateLimit = codexRateLimits[window] {
            return TokenUsageMetric(
                provider: provider,
                window: window,
                usedTokens: 0,
                tokenLimit: 0,
                usedPercent: rateLimit.usedPercent,
                resetAt: rateLimit.resetAt,
                updatedAt: now,
                sourceDescription: rateLimit.sourceDescription,
                errorMessage: nil
            )
        }

        if provider == .claude, let rateLimit = claudeRateLimits[window] {
            return TokenUsageMetric(
                provider: provider,
                window: window,
                usedTokens: 0,
                tokenLimit: 0,
                usedPercent: rateLimit.usedPercent,
                resetAt: rateLimit.resetAt,
                updatedAt: now,
                sourceDescription: rateLimit.sourceDescription,
                errorMessage: nil
            )
        }

        if provider == .codex {
            return TokenUsageMetric(
                provider: provider,
                window: window,
                usedTokens: 0,
                tokenLimit: 0,
                usedPercent: nil,
                resetAt: nil,
                updatedAt: now,
                sourceDescription: "~/.codex/logs_2.sqlite rate_limits",
                errorMessage: "No Codex rate-limit event found"
            )
        }

        if provider == .claude {
            return TokenUsageMetric(
                provider: provider,
                window: window,
                usedTokens: 0,
                tokenLimit: 0,
                usedPercent: nil,
                resetAt: nil,
                updatedAt: now,
                sourceDescription: "~/.claude/token-widget/claude-rate-limits.json",
                errorMessage: "No Claude statusline rate-limit capture found"
            )
        }

        return TokenUsageMetric(
            provider: provider,
            window: window,
            usedTokens: 0,
            tokenLimit: 0,
            usedPercent: nil,
            resetAt: nil,
            updatedAt: now,
            sourceDescription: "rate_limits",
            errorMessage: "No rate-limit data found"
        )
    }
}

struct TokenUsageSample {
    var timestamp: Date
    var tokens: Int
}

struct RateLimitWindow {
    var usedPercent: Double
    var resetAt: Date?
    var sourceDescription: String
}

struct CodexUsageReader {
    func readSamples() -> [TokenUsageSample] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let databasePath = "\(home)/.codex/state_5.sqlite"
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }

        let query = "select coalesce(updated_at_ms, updated_at * 1000), tokens_used from threads where tokens_used > 0;"
        let output = run("/usr/bin/sqlite3", arguments: [databasePath, query])

        return output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "|")
                guard parts.count == 2,
                      let milliseconds = Double(parts[0]),
                      let tokens = Int(parts[1])
                else {
                    return nil
                }

                return TokenUsageSample(
                    timestamp: Date(timeIntervalSince1970: milliseconds / 1000),
                    tokens: tokens
                )
            }
    }
}

struct CodexRateLimitReader {
    func readRateLimits() -> [UsageWindow: RateLimitWindow] {
        if let limits = readRateLimitsFromLatestSession() {
            return limits
        }

        return readRateLimitsFromSQLite()
    }

    private func readRateLimitsFromLatestSession() -> [UsageWindow: RateLimitWindow]? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsURL = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let sessionFiles = latestSessionFiles(in: sessionsURL)

        for fileURL in sessionFiles {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for line in text.split(separator: "\n").reversed() {
                guard line.contains("\"rate_limits\""),
                      let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = json["payload"] as? [String: Any],
                      let rateLimits = payload["rate_limits"] as? [String: Any]
                else {
                    continue
                }

                let source = "~/.codex/sessions rate_limits"
                let limits = parseRateLimits(rateLimits, sourceDescription: source)
                if !limits.isEmpty {
                    return limits
                }
            }
        }

        return nil
    }

    private func latestSessionFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modifiedAt: Date)] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true
            else {
                continue
            }

            files.append((fileURL, resourceValues.contentModificationDate ?? .distantPast))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(20)
            .map(\.url)
    }

    private func readRateLimitsFromSQLite() -> [UsageWindow: RateLimitWindow] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let databasePath = "\(home)/.codex/logs_2.sqlite"
        guard FileManager.default.fileExists(atPath: databasePath) else { return [:] }

        let query = """
        select feedback_log_body from logs
        where feedback_log_body like '%"type":"codex.rate_limits"%'
        order by ts desc, ts_nanos desc, id desc
        limit 1;
        """
        let output = run("/usr/bin/sqlite3", arguments: [databasePath, query])
        guard let jsonText = extractEventJSON(from: output),
              let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = json["rate_limits"] as? [String: Any]
        else {
            return [:]
        }

        return parseRateLimits(rateLimits, sourceDescription: "~/.codex/logs_2.sqlite rate_limits")
    }

    private func extractEventJSON(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let markerRange = trimmed.range(of: "websocket event: ") {
            return String(trimmed[markerRange.upperBound...])
        }

        guard let typeRange = trimmed.range(of: "\"type\":\"codex.rate_limits\"") else {
            return nil
        }

        var index = typeRange.lowerBound
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            if trimmed[previous] == "{" {
                return String(trimmed[previous...])
            }
            index = previous
        }

        return nil
    }

    private func parseRateLimits(
        _ rateLimits: [String: Any],
        sourceDescription: String
    ) -> [UsageWindow: RateLimitWindow] {
        var limits: [UsageWindow: RateLimitWindow] = [:]

        if let primary = parseWindow(rateLimits["primary"]) {
            limits[.fiveHours] = RateLimitWindow(
                usedPercent: primary.usedPercent,
                resetAt: primary.resetAt,
                sourceDescription: sourceDescription
            )
        }

        if let secondary = parseWindow(rateLimits["secondary"]) {
            limits[.weekly] = RateLimitWindow(
                usedPercent: secondary.usedPercent,
                resetAt: secondary.resetAt,
                sourceDescription: sourceDescription
            )
        }

        return limits
    }

    private func parseWindow(_ value: Any?) -> ParsedCodexLimitWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = dictionary["used_percent"] as? Double
                ?? (dictionary["used_percent"] as? Int).map(Double.init)
        else {
            return nil
        }

        let resetValue = dictionary["reset_at"] ?? dictionary["resets_at"]
        let resetAtSeconds = resetValue as? Double
            ?? (resetValue as? Int).map(Double.init)
        let resetAt = resetAtSeconds.map { Date(timeIntervalSince1970: $0) }
        return ParsedCodexLimitWindow(usedPercent: usedPercent, resetAt: resetAt)
    }
}

private struct ParsedCodexLimitWindow {
    var usedPercent: Double
    var resetAt: Date?
}

struct ClaudeRateLimitReader {
    func readRateLimits() -> [UsageWindow: RateLimitWindow] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".claude/token-widget/claude-rate-limits.json")

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = json["rate_limits"] as? [String: Any]
        else {
            return [:]
        }

        var limits: [UsageWindow: RateLimitWindow] = [:]
        let source = "~/.claude/token-widget/claude-rate-limits.json"

        if let fiveHour = parseWindow(rateLimits["five_hour"]) {
            limits[.fiveHours] = RateLimitWindow(
                usedPercent: fiveHour.usedPercent,
                resetAt: fiveHour.resetAt,
                sourceDescription: source
            )
        }

        if let sevenDay = parseWindow(rateLimits["seven_day"]) {
            limits[.weekly] = RateLimitWindow(
                usedPercent: sevenDay.usedPercent,
                resetAt: sevenDay.resetAt,
                sourceDescription: source
            )
        }

        return limits
    }

    private func parseWindow(_ value: Any?) -> ParsedClaudeLimitWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = number(dictionary["used_percentage"])
        else {
            return nil
        }

        let resetAt = number(dictionary["resets_at"])
            .map { Date(timeIntervalSince1970: $0) }
        return ParsedClaudeLimitWindow(usedPercent: usedPercent, resetAt: resetAt)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? String {
            return Double(value)
        }

        return nil
    }
}

private struct ParsedClaudeLimitWindow {
    var usedPercent: Double
    var resetAt: Date?
}

struct ClaudeUsageReader {
    func readSamples() -> [TokenUsageSample] {
        readStatsCacheSamples() + readReadOnceSamples()
    }

    private func readStatsCacheSamples() -> [TokenUsageSample] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/.claude/stats-cache.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dailyModelTokens = json["dailyModelTokens"] as? [[String: Any]]
        else {
            return []
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return dailyModelTokens.compactMap { item in
            guard let dateString = item["date"] as? String,
                  let date = formatter.date(from: dateString),
                  let tokensByModel = item["tokensByModel"] as? [String: Any]
            else {
                return nil
            }

            let tokens = tokensByModel.values.reduce(0) { partial, value in
                partial + (value as? Int ?? 0)
            }

            return TokenUsageSample(timestamp: date, tokens: tokens)
        }
    }

    private func readReadOnceSamples() -> [TokenUsageSample] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let url = URL(fileURLWithPath: "\(home)/.claude/read-once/stats.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = json["ts"] as? TimeInterval,
                      let tokens = json["tokens"] as? Int
                else {
                    return nil
                }

                return TokenUsageSample(
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    tokens: tokens
                )
            }
    }
}

@discardableResult
func run(_ executable: String, arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
