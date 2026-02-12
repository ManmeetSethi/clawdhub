//
//  ClawdHubApp.swift
//  ClawdHub
//
//  A native macOS menubar utility for monitoring Claude Code agent sessions
//

import SwiftUI

@main
struct ClawdHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(appDelegate.appSettings)
        }
    }
}
