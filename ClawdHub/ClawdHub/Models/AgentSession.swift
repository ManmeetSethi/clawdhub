//
//  AgentSession.swift
//  ClawdHub
//
//  Data model for a Claude Code agent session
//

import Foundation

struct AgentSession: Identifiable, Codable, Equatable {
    let id: String
    var status: AgentStatus
    var cwd: String
    var tty: String
    var terminal: String
    var startedAt: Date
    var updatedAt: Date
    var toolName: String?
    var activity: String?
    var notificationMessage: String?

    // MARK: - Coding Keys (for JSON snake_case mapping)

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case status
        case cwd
        case tty
        case terminal
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case toolName = "tool_name"
        case activity
        case notificationMessage = "notification_message"
    }

    // MARK: - Computed Properties

    /// Returns the last path component of the working directory (project folder name)
    var projectName: String {
        return (cwd as NSString).lastPathComponent
    }

    /// Returns the path with home directory abbreviated as ~
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    /// Returns a human-readable duration string since the session started
    var duration: String {
        let interval = Date().timeIntervalSince(startedAt)
        return Self.formatDuration(interval)
    }

    /// Returns a human-readable duration string since last activity
    var timeSinceActivity: String {
        let interval = Date().timeIntervalSince(updatedAt)
        return Self.formatDuration(interval)
    }

    /// Formats a time interval into a human-readable string
    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Returns a summary of current activity for card display
    var activitySummary: String? {
        switch status {
        case .running:
            if let tool = toolName, let act = activity {
                return "> \(tool) \(act)"
            } else if let tool = toolName {
                return "> \(tool)"
            }
            return nil
        case .waitingInput:
            if let msg = notificationMessage {
                return msg
            }
            return "Needs attention"
        case .idle:
            if let tool = toolName, let act = activity {
                return "Last: \(tool) \(act)"
            } else if let tool = toolName {
                return "Last: \(tool)"
            }
            return nil
        case .error:
            return nil
        }
    }

    /// Returns the detected terminal application name for display
    var terminalDisplayName: String {
        let normalizedTerminal = terminal.lowercased()

        switch normalizedTerminal {
        case "iterm.app", "iterm2", "iterm":
            return "iTerm2"
        case "apple_terminal", "terminal", "terminal.app":
            return "Terminal"
        case "ghostty":
            return "Ghostty"
        case "wezterm":
            return "WezTerm"
        case "alacritty":
            return "Alacritty"
        case "kitty":
            return "Kitty"
        case "vscode", "code", "visual studio code":
            return "VS Code"
        case "cursor":
            return "Cursor"
        case "warp", "warpterminal":
            return "Warp"
        default:
            return terminal.isEmpty ? "Unknown" : terminal
        }
    }
}

// MARK: - Custom Date Decoding

extension AgentSession {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(AgentStatus.self, forKey: .status)
        cwd = try container.decode(String.self, forKey: .cwd)
        tty = try container.decode(String.self, forKey: .tty)
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal) ?? "unknown"
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        activity = try container.decodeIfPresent(String.self, forKey: .activity)
        notificationMessage = try container.decodeIfPresent(String.self, forKey: .notificationMessage)

        // Handle ISO8601 date strings
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startedAtString = try container.decode(String.self, forKey: .startedAt)
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)

        // Try with fractional seconds first, then without
        if let date = dateFormatter.date(from: startedAtString) {
            startedAt = date
        } else {
            dateFormatter.formatOptions = [.withInternetDateTime]
            startedAt = dateFormatter.date(from: startedAtString) ?? Date()
        }

        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = dateFormatter.date(from: updatedAtString) {
            updatedAt = date
        } else {
            dateFormatter.formatOptions = [.withInternetDateTime]
            updatedAt = dateFormatter.date(from: updatedAtString) ?? Date()
        }
    }
}

// MARK: - Comparable (for sorting)

extension AgentSession: Comparable {
    static func < (lhs: AgentSession, rhs: AgentSession) -> Bool {
        // Sort by priority: waitingInput > running > stopped/error
        let lhsPriority = lhs.sortPriority
        let rhsPriority = rhs.sortPriority

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        // Within same priority, sort by most recent activity
        return lhs.updatedAt > rhs.updatedAt
    }

    private var sortPriority: Int {
        switch status {
        case .waitingInput:
            return 0
        case .running:
            return 1
        case .idle:
            return 2
        case .error:
            return 3
        }
    }
}
