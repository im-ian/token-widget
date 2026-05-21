import AppKit
import SwiftUI
import WidgetKit

@main
struct TokenWidgetApp: App {
    @NSApplicationDelegateAdaptor(TokenWidgetAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class TokenWidgetAppDelegate: NSObject, NSApplicationDelegate {
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        refreshTask = Task { @MainActor in
            await TokenWidgetBackgroundRefresher().run()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }
}

@MainActor
struct TokenWidgetBackgroundRefresher {
    private let store = TokenUsageStore()
    private let refreshService = TokenUsageRefreshService()

    func run() async {
        await refresh()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func refresh() async {
        let preferences = store.loadPreferences()
        let snapshot = await refreshService.refresh(preferences: preferences)
        store.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
