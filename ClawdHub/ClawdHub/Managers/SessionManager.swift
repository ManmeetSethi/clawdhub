//
//  SessionManager.swift
//  ClawdHub
//
//  Manages Claude Code agent session state by watching the sessions file
//

import Foundation
import Combine

class SessionManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var sessions: [AgentSession] = []

    // MARK: - Callbacks

    var onSessionNeedsAttention: ((AgentSession) -> Void)?
    var onSessionFinished: ((AgentSession) -> Void)?

    // MARK: - Private Properties

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let sessionsFileURL: URL
    private let claudeControlDirectory: URL
    private var previousSessionStates: [String: AgentStatus] = [:]
    private var debounceTimer: Timer?

    // MARK: - Computed Properties

    /// Sessions sorted by priority (waiting first, then running, then stopped)
    var sortedSessions: [AgentSession] {
        return sessions.sorted()
    }

    /// Sessions that need user attention
    var sessionsNeedingAttention: [AgentSession] {
        return sessions.filter { $0.status == .waitingInput }
    }

    /// Count of sessions needing attention
    var attentionCount: Int {
        return sessionsNeedingAttention.count
    }

    /// Whether any session needs attention
    var hasSessionsNeedingAttention: Bool {
        return !sessionsNeedingAttention.isEmpty
    }

    // MARK: - Initialization

    private var refreshTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeControlDirectory = home.appendingPathComponent(".clawdhub")
        sessionsFileURL = claudeControlDirectory.appendingPathComponent("sessions.json")

        ensureDirectoryExists()
        loadSessions()
        setupFileWatcher()
        setupPeriodicRefresh()
    }

    private func setupPeriodicRefresh() {
        // Fallback: refresh every 2 seconds in case file watcher misses changes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.loadSessions()
        }
    }

    deinit {
        stopFileWatcher()
    }

    // MARK: - Directory Setup

    private func ensureDirectoryExists() {
        do {
            try FileManager.default.createDirectory(
                at: claudeControlDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Create empty sessions file if it doesn't exist
            if !FileManager.default.fileExists(atPath: sessionsFileURL.path) {
                try "[]".write(to: sessionsFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to create clawdhub directory: \(error)")
        }
    }

    // MARK: - File Watching

    private func setupFileWatcher() {
        // First, ensure the file exists
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else {
            print("Sessions file does not exist yet")
            // Try again in a second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.setupFileWatcher()
            }
            return
        }

        fileDescriptor = open(sessionsFileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open sessions file for watching")
            return
        }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        fileWatcher?.setEventHandler { [weak self] in
            self?.handleFileChange()
        }

        fileWatcher?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        fileWatcher?.resume()
    }

    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    private func handleFileChange() {
        // Check if file was deleted/renamed (atomic write) - need to re-establish watcher
        if let source = fileWatcher {
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced, re-establish watcher
                stopFileWatcher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.setupFileWatcher()
                }
            }
        }

        // Debounce rapid changes
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.loadSessions()
        }
    }

    // MARK: - Session Loading

    func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else {
            sessions = []
            return
        }

        do {
            let data = try Data(contentsOf: sessionsFileURL)
            guard !data.isEmpty else {
                sessions = []
                return
            }
            let decoder = JSONDecoder()
            // Decode sessions individually — skip any with unrecognized status
            // so one bad entry doesn't break the entire list
            let rawSessions = try decoder.decode([SafeDecodable<AgentSession>].self, from: data)
            let loadedSessions = rawSessions.compactMap { $0.value }

            // Filter out stale sessions:
            // - Any session older than 24 hours (likely orphaned)
            // - Any session started before hooks were installed
            let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
            let hookInstalledAt = UserDefaults.standard.double(forKey: "hookInstalledAt")
            let installDate = hookInstalledAt > 0 ? Date(timeIntervalSince1970: hookInstalledAt) : nil

            let filteredSessions = loadedSessions.filter { session in
                if session.updatedAt < twentyFourHoursAgo { return false }
                if let installDate = installDate, session.startedAt < installDate { return false }
                return true
            }

            // If we filtered out sessions, persist the cleanup
            if filteredSessions.count < loadedSessions.count {
                DispatchQueue.main.async { [weak self] in
                    self?.saveSessions(filteredSessions)
                }
            }

            // Check for state changes and trigger callbacks
            for session in filteredSessions {
                let previousStatus = previousSessionStates[session.id]

                if previousStatus == nil {
                    // New session detected
                    AnalyticsManager.shared.track("session_detected", properties: [
                        "terminal": session.terminalDisplayName
                    ])
                }

                if previousStatus != session.status {
                    if session.status == .waitingInput {
                        onSessionNeedsAttention?(session)
                    } else if session.status == .idle && (previousStatus == .running || previousStatus == .waitingInput) {
                        onSessionFinished?(session)
                    }
                }

                previousSessionStates[session.id] = session.status
            }

            // Clean up old session states
            let currentIds = Set(filteredSessions.map { $0.id })
            previousSessionStates = previousSessionStates.filter { currentIds.contains($0.key) }

            sessions = filteredSessions
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    // MARK: - Session Cleanup

    /// Removes stale sessions that no longer have an active TTY
    func cleanupStaleSessions() {
        let activeSessions = sessions.filter { session in
            // Check if TTY still exists and has an active process
            let tty = session.tty
            guard !tty.isEmpty && tty != "unknown" else { return false }

            // Simple check: see if the TTY device exists
            return FileManager.default.fileExists(atPath: tty)
        }

        if activeSessions.count != sessions.count {
            saveSessions(activeSessions)
        }
    }

    /// Removes a specific session
    func removeSession(id: String) {
        let filtered = sessions.filter { $0.id != id }
        saveSessions(filtered)
    }

    private func saveSessions(_ sessions: [AgentSession]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(sessions)
            try data.write(to: sessionsFileURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    // MARK: - Demo Sessions

    private var isDemoMode = false

    func setDemoSessions(_ demoSessions: [AgentSession]) {
        isDemoMode = true
        stopFileWatcher()
        refreshTimer?.invalidate()
        refreshTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        sessions = demoSessions
    }

    func clearDemoSessions() {
        isDemoMode = false
        loadSessions()
        setupFileWatcher()
        setupPeriodicRefresh()
    }

    // MARK: - Manual Refresh

    func refresh() {
        loadSessions()
    }
}

// MARK: - Safe Decoding Helper

/// Wraps decoding so that individual element failures don't break the entire array
struct SafeDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}
