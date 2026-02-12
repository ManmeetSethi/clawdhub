//
//  SettingsView.swift
//  ClawdHub
//
//  App settings window
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
                    .help("Automatically start ClawdHub when you log in")
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text("Hotkey")
                    Spacer()
                    Text(appSettings.hotkeyDisplayString)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Hold to peek at agents, double-tap Command to persist the panel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Agent needs permission", isOn: $appSettings.notifyOnPermission)
                    .help("Show a notification when an agent is waiting for your input")

                Toggle("Agent finished", isOn: $appSettings.notifyOnFinish)
                    .help("Show a notification when an agent completes its task")
            } header: {
                Text("Notify When")
            }

            Section {
                Toggle("Play sounds", isOn: $appSettings.playSounds)
                    .help("Play a sound with notifications")
            } header: {
                Text("Sound")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon placeholder
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("ClawdHub")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(appSettings.appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Monitor and manage your Claude Code agent sessions")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/anthropics/claude-code")!) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.link)

                Link(destination: URL(string: "https://docs.anthropic.com/claude-code")!) {
                    Label("Documentation", systemImage: "book")
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
