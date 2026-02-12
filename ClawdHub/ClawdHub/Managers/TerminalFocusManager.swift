//
//  TerminalFocusManager.swift
//  ClawdHub
//
//  Handles focusing terminal applications and specific tabs using AppleScript and NSWorkspace
//

import Foundation
import AppKit

// MARK: - TerminalApp Enum

/// Supported terminal applications with their bundle identifiers
enum TerminalApp: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case iterm2 = "com.googlecode.iterm2"
    case vscode = "com.microsoft.VSCode"
    case cursor = "com.todesktop.230313mzl4w4u92"
    case ghostty = "com.mitchellh.ghostty"
    case wezterm = "com.github.wez.wezterm"
    case alacritty = "io.alacritty"
    case kitty = "net.kovidgoyal.kitty"
    case warp = "dev.warp.Warp-Stable"

    var bundleId: String {
        return rawValue
    }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .ghostty: return "Ghostty"
        case .wezterm: return "WezTerm"
        case .alacritty: return "Alacritty"
        case .kitty: return "Kitty"
        case .warp: return "Warp"
        }
    }

    /// Whether this terminal supports TTY-based tab matching via AppleScript
    var supportsTTYMatching: Bool {
        switch self {
        case .terminal, .iterm2:
            return true
        default:
            return false
        }
    }

    /// Initialize from TERM_PROGRAM environment variable value
    static func from(termProgram: String) -> TerminalApp? {
        let normalized = termProgram.lowercased()
        switch normalized {
        case "iterm.app", "iterm2", "iterm":
            return .iterm2
        case "apple_terminal", "terminal", "terminal.app":
            return .terminal
        case "ghostty":
            return .ghostty
        case "wezterm":
            return .wezterm
        case "alacritty":
            return .alacritty
        case "kitty":
            return .kitty
        case "vscode", "code", "visual studio code":
            return .vscode  // Note: Cursor also reports as vscode
        case "cursor":
            return .cursor
        case "warp", "warpterminal":
            return .warp
        default:
            return nil
        }
    }
}

class TerminalFocusManager {

    // MARK: - Public Methods

    /// Focus the terminal window/tab for a given session
    func focusTerminal(for session: AgentSession) {
        print("[TerminalFocusManager] focusTerminal called")
        print("[TerminalFocusManager] session.terminal: \(session.terminal)")
        print("[TerminalFocusManager] session.tty: \(session.tty)")

        let terminal = session.terminal.lowercased()
        let tty = normalizedTTY(session.tty)

        print("[TerminalFocusManager] Matching terminal: \(terminal), normalized TTY: \(tty)")

        // Handle VS Code / Cursor ambiguity
        // Both Cursor and VS Code report TERM_PROGRAM=vscode
        if terminal == "vscode" || terminal == "code" || terminal == "visual studio code" {
            focusVSCodeOrCursor(cwd: session.cwd)
            return
        }

        // Try to get the terminal app from the TERM_PROGRAM value
        guard let terminalApp = TerminalApp.from(termProgram: terminal) else {
            // Unknown terminal - try fallback
            print("[TerminalFocusManager] Unknown terminal '\(terminal)', trying fallback")
            focusFallback()
            return
        }

        // For terminals that support TTY matching (Terminal.app, iTerm2)
        if terminalApp.supportsTTYMatching && tty != "unknown" {
            switch terminalApp {
            case .iterm2:
                focusITerm2WithTTY(tty: tty)
            case .terminal:
                focusTerminalAppWithTTY(tty: tty)
            default:
                activateByBundleId(terminalApp.bundleId)
            }
        } else {
            // For all other terminals, just activate by bundle ID
            activateByBundleId(terminalApp.bundleId)
        }
    }

    // MARK: - Bundle ID Activation

    /// Activate an application by its bundle identifier using NSWorkspace
    /// This avoids AppleScript "Where is X?" dialogs for uninstalled apps
    private func activateByBundleId(_ bundleId: String) {
        print("[TerminalFocusManager] Activating by bundle ID: \(bundleId)")

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            print("[TerminalFocusManager] App with bundle ID \(bundleId) is not running")
            return
        }

        let success = app.activate(options: [.activateIgnoringOtherApps])
        if !success {
            print("[TerminalFocusManager] Failed to activate app with bundle ID \(bundleId)")
        }
    }

    /// Check if an application with the given bundle ID is running
    private func isAppRunning(_ bundleId: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    // MARK: - VS Code / Cursor Window Targeting

    /// Handle VS Code or Cursor focusing with window targeting
    /// Both report TERM_PROGRAM=vscode, so we check which one is running
    ///
    /// Strategy: Use the CLI (`cursor -r <folder>` / `code -r <folder>`) to focus
    /// the window with the matching folder open. This is more reliable than AppleScript
    /// because Electron apps (Cursor) don't expose windows to AppleScript or System Events.
    private func focusVSCodeOrCursor(cwd: String) {
        print("[TerminalFocusManager] Checking for Cursor or VS Code, cwd: \(cwd)")

        let cursorRunning = isAppRunning(TerminalApp.cursor.bundleId)
        let vscodeRunning = isAppRunning(TerminalApp.vscode.bundleId)

        // Use CLI to focus the correct window — -r reuses the existing window for this folder
        if cursorRunning {
            print("[TerminalFocusManager] Cursor is running, using CLI to focus: \(cwd)")
            if focusIDEViaCLI(cliPath: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor", cwd: cwd) {
                return
            }
        }

        if vscodeRunning {
            print("[TerminalFocusManager] VS Code is running, using CLI to focus: \(cwd)")
            if focusIDEViaCLI(cliPath: "/usr/local/bin/code", cwd: cwd) {
                return
            }
        }

        // Fallback: just activate whichever is running
        print("[TerminalFocusManager] CLI focus failed, falling back to activation")
        if cursorRunning {
            activateByBundleId(TerminalApp.cursor.bundleId)
        } else if vscodeRunning {
            activateByBundleId(TerminalApp.vscode.bundleId)
        } else {
            print("[TerminalFocusManager] Neither Cursor nor VS Code is running")
            focusFallback()
        }
    }

    /// Focus an IDE window by using its CLI with --reuse-window flag.
    /// `cursor -r /path/to/folder` focuses the existing window with that folder open.
    /// Returns true if the CLI was found and executed.
    private func focusIDEViaCLI(cliPath: String, cwd: String) -> Bool {
        guard FileManager.default.fileExists(atPath: cliPath) else {
            print("[TerminalFocusManager] CLI not found at \(cliPath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-r", cwd]
        // Detach — don't wait for completion (CLI may stay open)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            print("[TerminalFocusManager] CLI launched: \(cliPath) -r \(cwd)")
            return true
        } catch {
            print("[TerminalFocusManager] CLI failed: \(error)")
            return false
        }
    }

    // MARK: - iTerm2 TTY Matching

    private func focusITerm2WithTTY(tty: String) {
        let script = """
        tell application id "com.googlecode.iterm2"
            set targetTTY to "\(escapedTTY(tty))"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        try
                            if tty of aSession is targetTTY then
                                select aTab
                                set index of aWindow to 1
                                activate
                                return
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """

        runAppleScript(script)
    }

    // MARK: - Terminal.app TTY Matching

    private func focusTerminalAppWithTTY(tty: String) {
        let script = """
        tell application id "com.apple.Terminal"
            set targetTTY to "\(escapedTTY(tty))"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    try
                        if tty of aTab is targetTTY then
                            set selected tab of aWindow to aTab
                            set index of aWindow to 1
                            activate
                            return
                        end if
                    end try
                end repeat
            end repeat
            activate
        end tell
        """

        runAppleScript(script)
    }

    // MARK: - Fallback

    /// Fallback: Try to find any running terminal app and activate it
    private func focusFallback() {
        print("[TerminalFocusManager] Trying fallback - looking for any running terminal")

        // Priority order for fallback
        let fallbackOrder: [TerminalApp] = [
            .iterm2,
            .terminal,
            .ghostty,
            .wezterm,
            .kitty,
            .alacritty,
            .warp,
            .cursor,
            .vscode
        ]

        for app in fallbackOrder {
            if isAppRunning(app.bundleId) {
                print("[TerminalFocusManager] Found running terminal: \(app.displayName)")
                activateByBundleId(app.bundleId)
                return
            }
        }

        print("[TerminalFocusManager] No known terminal app is running")
    }

    // MARK: - AppleScript Execution

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
                if let error = error {
                    print("AppleScript error: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Normalize TTY value, returning "unknown" for invalid values
    private func normalizedTTY(_ tty: String) -> String {
        let cleaned = tty
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty ||
           cleaned == "unknown" ||
           cleaned.contains("not a tty") ||
           cleaned == "?" {
            return "unknown"
        }

        return cleaned
    }

    /// Escape TTY string for use in AppleScript
    private func escapedTTY(_ tty: String) -> String {
        return tty
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
