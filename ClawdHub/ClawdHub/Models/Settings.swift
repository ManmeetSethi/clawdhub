//
//  Settings.swift
//  ClawdHub
//
//  App settings model with UserDefaults persistence
//

import Foundation
import SwiftUI
import ServiceManagement

class AppSettings: ObservableObject {

    // MARK: - Persisted Settings

    @AppStorage("launchAtLogin") var launchAtLogin = false {
        didSet {
            updateLaunchAtLogin()
        }
    }

    @AppStorage("notifyOnPermission") var notifyOnPermission = true
    @AppStorage("notifyOnFinish") var notifyOnFinish = true
    @AppStorage("playSounds") var playSounds = true

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("telemetryEnabled") var telemetryEnabled = false {
        didSet {
            AnalyticsManager.shared.setEnabled(telemetryEnabled)
        }
    }

    // MARK: - Non-Persisted State

    /// Whether the hotkey is currently being customized (future feature)
    @Published var isCustomizingHotkey = false

    // MARK: - Computed Properties

    /// Current hotkey display string
    var hotkeyDisplayString: String {
        return "⌥⌘ (Option + Command)"
    }

    /// App version string
    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }

    /// Syncs the launch at login setting with the system state
    func syncLaunchAtLoginState() {
        let systemState = SMAppService.mainApp.status == .enabled
        if systemState != launchAtLogin {
            launchAtLogin = systemState
        }
    }

    // MARK: - Initialization

    init() {
        // Sync launch at login state on init
        syncLaunchAtLoginState()
    }
}
