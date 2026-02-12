//
//  AnalyticsManager.swift
//  ClawdHub
//
//  Lightweight Mixpanel analytics via HTTP API — no SDK dependency.
//  Respects appSettings.telemetryEnabled; all tracking is anonymous.
//

import Foundation

final class AnalyticsManager {

    static let shared = AnalyticsManager()

    // MARK: - Configuration

    private let token = "f6aa2f0b5921886b9fa81a8dcad8184b"
    private let endpoint = URL(string: "https://api.mixpanel.com/track")!
    private let profileEndpoint = URL(string: "https://api.mixpanel.com/engage")!

    // MARK: - State

    private var enabled = false
    private let distinctId: String
    private let session = URLSession(configuration: .ephemeral)

    // MARK: - Init

    private init() {
        // Generate or retrieve a stable anonymous ID
        let key = "analyticsDistinctId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            distinctId = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            distinctId = newId
        }
    }

    // MARK: - Configuration

    /// Call once at app launch. Reads telemetryEnabled from AppSettings.
    func configure(enabled: Bool) {
        self.enabled = enabled
    }

    /// Update opt-in state (e.g. when user toggles in settings or onboarding).
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    // MARK: - Track Event

    /// Track an event (respects telemetry opt-in).
    func track(_ event: String, properties: [String: Any] = [:]) {
        guard enabled else { return }
        send(event: event, properties: properties)
    }

    /// Track an event regardless of opt-in. Use only for onboarding funnel
    /// events where we need drop-off data before the user has toggled telemetry.
    func trackAlways(_ event: String, properties: [String: Any] = [:]) {
        send(event: event, properties: properties)
    }

    /// Track an event with a random one-time distinct_id, making it unlinkable
    /// to the user's persistent analytics profile. Use for PII submissions.
    func trackAnonymous(_ event: String, properties: [String: Any] = [:]) {
        var props: [String: Any] = [
            "token": token,
            "distinct_id": UUID().uuidString,
            "time": Int(Date().timeIntervalSince1970),
            "$os": "macOS",
            "$os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        ]
        for (key, value) in properties { props[key] = value }
        let payload: [String: Any] = ["event": event, "properties": props]
        send(to: endpoint, body: [payload])
    }

    private func send(event: String, properties: [String: Any]) {
        var props: [String: Any] = [
            "token": token,
            "distinct_id": distinctId,
            "time": Int(Date().timeIntervalSince1970),
            "$os": "macOS",
            "$os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        ]

        // Merge caller properties (caller wins on conflict)
        for (key, value) in properties {
            props[key] = value
        }

        let payload: [String: Any] = [
            "event": event,
            "properties": props
        ]

        send(to: endpoint, body: [payload])
    }

    // MARK: - Set User Properties

    func setUserProperties(_ properties: [String: Any]) {
        guard enabled else { return }

        let payload: [String: Any] = [
            "$token": token,
            "$distinct_id": distinctId,
            "$set": properties
        ]

        send(to: profileEndpoint, body: [payload])
    }

    // MARK: - HTTP

    private func send(to url: URL, body: [[String: Any]]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        session.dataTask(with: request) { _, _, _ in
            // Fire and forget — no error handling needed for analytics
        }.resume()
    }
}
