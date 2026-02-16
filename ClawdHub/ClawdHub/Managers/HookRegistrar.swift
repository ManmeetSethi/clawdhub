//
//  HookRegistrar.swift
//  ClawdHub
//
//  Manages Claude Code hook registration and script creation
//

import Foundation

class HookRegistrar {

    // MARK: - Properties

    private let homeDirectory: URL
    private let claudeControlDirectory: URL
    private let hooksDirectory: URL
    private let claudeSettingsURL: URL

    // MARK: - Initialization

    init() {
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        claudeControlDirectory = homeDirectory.appendingPathComponent(".clawdhub")
        hooksDirectory = claudeControlDirectory.appendingPathComponent("hooks")
        claudeSettingsURL = homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Public Methods

    func registerHooksIfNeeded() {
        createDirectories()
        clearSessionsOnFirstInstall()
        createHookScripts()
        updateClaudeSettings()
    }

    private func clearSessionsOnFirstInstall() {
        let hasInstalledBefore = UserDefaults.standard.object(forKey: "hookInstalledAt") != nil
        if !hasInstalledBefore {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "hookInstalledAt")
            // Only clear sessions.json on fresh install (not upgrade)
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                let sessionsFile = claudeControlDirectory.appendingPathComponent("sessions.json")
                try? "[]".write(to: sessionsFile, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Directory Setup

    private func createDirectories() {
        do {
            try FileManager.default.createDirectory(
                at: hooksDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Failed to create hooks directory: \(error)")
        }
    }

    // MARK: - Shared Locking

    /// Bash snippet for file locking + JSON validation.
    /// Uses mkdir (atomic on APFS/HFS+) with stale lock cleanup and trap-based release.
    /// Prevents race conditions when multiple hook invocations run concurrently.
    private let lockingPreamble = """
    # Acquire file lock (mkdir is atomic)
    if [ -d "$LOCKDIR" ]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
        [ "$LOCK_AGE" -gt 5 ] && rmdir "$LOCKDIR" 2>/dev/null
    fi
    for _i in $(seq 1 40); do
        mkdir "$LOCKDIR" 2>/dev/null && break
        [ "$_i" -eq 40 ] && exit 0
        sleep 0.05
    done
    trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

    # Ensure file exists, is non-empty, and is valid JSON
    [ ! -s "$SESSIONS_FILE" ] && echo "[]" > "$SESSIONS_FILE"
    /usr/bin/jq '.' "$SESSIONS_FILE" > /dev/null 2>&1 || echo "[]" > "$SESSIONS_FILE"
    """

    // MARK: - Hook Scripts

    private func createHookScripts() {
        createOnNotificationScript()
        createOnStopScript()
        createOnSessionEndScript()
        createOnActivityScript()
        createOnUserPromptScript()
        createOnPostToolScript()
    }

    private func createOnNotificationScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - notification event
        # Only sets waiting_input for actionable notification types
        # Extracts notification message for display

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID and notification type
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        NOTIFICATION_TYPE=$(echo "$INPUT" | /usr/bin/jq -r '.notification_type // empty')

        # Only set waiting_input for actionable notification types
        case "$NOTIFICATION_TYPE" in
            permission_prompt|elicitation_dialog)
                # These need user attention
                ;;
            *)
                # Other notification types (auth_success, etc.) - no state change
                exit 0
                ;;
        esac

        # Extract notification message
        NOTIFICATION_MSG=$(echo "$INPUT" | /usr/bin/jq -r '.message // empty')
        [ -z "$NOTIFICATION_MSG" ] && NOTIFICATION_MSG="Needs attention"

        # Gather context
        CWD=$(pwd)
        TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
        if [ -n "$TTY" ] && [ "$TTY" != "??" ]; then TTY="/dev/$TTY"; else TTY="unknown"; fi
        TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"
        mkdir -p "$(dirname "$SESSIONS_FILE")"

        \(lockingPreamble)

        # Update or add session with waiting_input status and notification message
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           --arg cwd "$CWD" \\
           --arg tty "$TTY" \\
           --arg term "$TERM_PROGRAM" \\
           --arg ts "$TIMESTAMP" \\
           --arg msg "$NOTIFICATION_MSG" \\
           '
           if any(.[]; .session_id == $sid) then
             map(if .session_id == $sid then . + {status: "waiting_input", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts, notification_message: $msg} else . end)
           else
             . + [{session_id: $sid, status: "waiting_input", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts, notification_message: $msg}]
           end
           ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-notification.sh")
    }

    private func createOnStopScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - Stop event (Claude finished responding)
        # Sets status to "idle" - Claude is done, waiting for next user prompt
        # Preserves tool_name and activity as last activity

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        # Gather context
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"

        [ ! -f "$SESSIONS_FILE" ] && exit 0

        \(lockingPreamble)

        # Update session status to idle, keep existing tool_name/activity, clear notification_message
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           --arg ts "$TIMESTAMP" \\
           '
           map(if .session_id == $sid then . + {status: "idle", updated_at: $ts, notification_message: null} else . end)
           ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-stop.sh")
    }

    private func createOnSessionEndScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - SessionEnd event (session terminated)
        # Removes session from JSON immediately

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"

        [ ! -f "$SESSIONS_FILE" ] && exit 0

        \(lockingPreamble)

        # Remove session from the array
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           'map(select(.session_id != $sid))' \\
           "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-session-end.sh")
    }

    private func createOnActivityScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - PreToolUse event (agent is running)
        # Extracts tool_name and derives activity summary

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        # Extract tool name
        TOOL_NAME=$(echo "$INPUT" | /usr/bin/jq -r '.tool_name // empty')

        # Derive activity summary based on tool type
        ACTIVITY=""
        case "$TOOL_NAME" in
            Bash)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.command // empty' | head -c 60 | head -1)
                ;;
            Read|Edit|Write)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.file_path // empty' | xargs basename 2>/dev/null)
                ;;
            Grep)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.pattern // empty' | head -c 40)
                ;;
            Glob)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.pattern // empty' | head -c 40)
                ;;
            Task)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.description // empty' | head -c 40)
                ;;
            WebFetch|WebSearch)
                ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.url // .tool_input.query // empty' | head -c 40)
                ;;
            *)
                ACTIVITY=""
                ;;
        esac

        # Gather context
        CWD=$(pwd)
        TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
        if [ -n "$TTY" ] && [ "$TTY" != "??" ]; then TTY="/dev/$TTY"; else TTY="unknown"; fi
        TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"
        mkdir -p "$(dirname "$SESSIONS_FILE")"

        \(lockingPreamble)

        # Update or add session with running status, tool_name, and activity
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           --arg cwd "$CWD" \\
           --arg tty "$TTY" \\
           --arg term "$TERM_PROGRAM" \\
           --arg ts "$TIMESTAMP" \\
           --arg tool "$TOOL_NAME" \\
           --arg act "$ACTIVITY" \\
           '
           if any(.[]; .session_id == $sid) then
             map(if .session_id == $sid then . + {status: "running", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts, tool_name: $tool, activity: $act, notification_message: null} else . end)
           else
             . + [{session_id: $sid, status: "running", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts, tool_name: $tool, activity: $act}]
           end
           ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-activity.sh")
    }

    private func createOnUserPromptScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - UserPromptSubmit event (user sent a message)
        # Sets status to "running" - user sent a prompt, Claude is about to work

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        # Gather context
        CWD=$(pwd)
        TTY=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
        if [ -n "$TTY" ] && [ "$TTY" != "??" ]; then TTY="/dev/$TTY"; else TTY="unknown"; fi
        TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"
        mkdir -p "$(dirname "$SESSIONS_FILE")"

        \(lockingPreamble)

        # Update or add session with running status
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           --arg cwd "$CWD" \\
           --arg tty "$TTY" \\
           --arg term "$TERM_PROGRAM" \\
           --arg ts "$TIMESTAMP" \\
           '
           if any(.[]; .session_id == $sid) then
             map(if .session_id == $sid then . + {status: "running", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts} else . end)
           else
             . + [{session_id: $sid, status: "running", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts}]
           end
           ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-user-prompt.sh")
    }

    private func createOnPostToolScript() {
        let script = """
        #!/bin/bash
        # ClawdHub hook - PostToolUse/PostToolUseFailure event
        # Sets status back to "running" after a tool completes
        # Clears notification_message (permission was granted if it was waiting)

        # Read JSON from stdin
        INPUT=$(cat)

        # Extract session ID
        SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
        [ -z "$SESSION_ID" ] && exit 0

        # Gather context
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # Sessions file location
        SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
        LOCKDIR="$SESSIONS_FILE.lock"

        [ ! -f "$SESSIONS_FILE" ] && exit 0

        \(lockingPreamble)

        # Update session status to running, clear notification_message
        /usr/bin/jq --arg sid "$SESSION_ID" \\
           --arg ts "$TIMESTAMP" \\
           '
           map(if .session_id == $sid then . + {status: "running", updated_at: $ts, notification_message: null} else . end)
           ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
        """

        writeScript(script, to: "on-post-tool.sh")
    }

    private func writeScript(_ content: String, to filename: String) {
        let scriptURL = hooksDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            print("Failed to write hook script \(filename): \(error)")
        }
    }

    // MARK: - Claude Settings

    private func updateClaudeSettings() {
        // Read existing settings
        var settings: [String: Any] = [:]

        if FileManager.default.fileExists(atPath: claudeSettingsURL.path) {
            do {
                let data = try Data(contentsOf: claudeSettingsURL)
                if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = existing
                }
            } catch {
                print("Failed to read existing Claude settings: \(error)")
            }
        }

        // Get or create hooks dictionary
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Add our hooks (preserving existing hooks)
        let hookTemplate: (String) -> [[String: Any]] = { scriptName in
            [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "~/.clawdhub/hooks/\(scriptName)"
                        ]
                    ]
                ]
            ]
        }

        // Merge hooks (add ours if not already present)
        hooks["Notification"] = mergeHooks(existing: hooks["Notification"], new: hookTemplate("on-notification.sh"))
        hooks["Stop"] = mergeHooks(existing: hooks["Stop"], new: hookTemplate("on-stop.sh"))
        hooks["SessionEnd"] = mergeHooks(existing: hooks["SessionEnd"], new: hookTemplate("on-session-end.sh"))
        hooks["PreToolUse"] = mergeHooks(existing: hooks["PreToolUse"], new: hookTemplate("on-activity.sh"))
        hooks["UserPromptSubmit"] = mergeHooks(existing: hooks["UserPromptSubmit"], new: hookTemplate("on-user-prompt.sh"))
        hooks["PostToolUse"] = mergeHooks(existing: hooks["PostToolUse"], new: hookTemplate("on-post-tool.sh"))
        hooks["PostToolUseFailure"] = mergeHooks(existing: hooks["PostToolUseFailure"], new: hookTemplate("on-post-tool.sh"))

        settings["hooks"] = hooks

        // Write back
        do {
            // Ensure .claude directory exists
            let claudeDir = homeDirectory.appendingPathComponent(".claude")
            try FileManager.default.createDirectory(
                at: claudeDir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: claudeSettingsURL, options: .atomic)
        } catch {
            print("Failed to update Claude settings: \(error)")
        }
    }

    private func mergeHooks(existing: Any?, new: [[String: Any]]) -> [[String: Any]] {
        guard let existingArray = existing as? [[String: Any]] else {
            return new
        }

        // Check if our hook is already registered
        let ourCommand = "~/.clawdhub/hooks/"
        let alreadyExists = existingArray.contains { hookConfig in
            guard let hooksArray = hookConfig["hooks"] as? [[String: Any]] else { return false }
            return hooksArray.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains(ourCommand)
            }
        }

        if alreadyExists {
            return existingArray
        }

        return existingArray + new
    }

    // MARK: - Unregistration

    func unregisterHooks() {
        // Remove our hooks from Claude settings
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return }

        do {
            let data = try Data(contentsOf: claudeSettingsURL)
            guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var hooks = settings["hooks"] as? [String: Any] else { return }

            let ourCommand = "~/.clawdhub/hooks/"

            for key in ["Notification", "Stop", "SessionEnd", "PreToolUse", "UserPromptSubmit", "PostToolUse", "PostToolUseFailure"] {
                guard var hookArray = hooks[key] as? [[String: Any]] else { continue }

                hookArray = hookArray.filter { hookConfig in
                    guard let hooksArray = hookConfig["hooks"] as? [[String: Any]] else { return true }
                    return !hooksArray.contains { hook in
                        guard let command = hook["command"] as? String else { return false }
                        return command.contains(ourCommand)
                    }
                }

                if hookArray.isEmpty {
                    hooks.removeValue(forKey: key)
                } else {
                    hooks[key] = hookArray
                }
            }

            settings["hooks"] = hooks

            let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: claudeSettingsURL, options: .atomic)
        } catch {
            print("Failed to unregister hooks: \(error)")
        }
    }
}
