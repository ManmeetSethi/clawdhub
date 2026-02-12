//
//  NotificationManager.swift
//  ClawdHub
//
//  Handles native macOS notifications for agent events
//

import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Callbacks

    var onNotificationClicked: ((String) -> Void)?

    // MARK: - Properties

    private var recentNotifications: Set<String> = []
    private let debounceInterval: TimeInterval = 0.5

    // MARK: - Notification Categories

    private let permissionCategoryId = "PERMISSION_NEEDED"
    private let finishedCategoryId = "AGENT_FINISHED"

    // MARK: - Initialization

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
    }

    // MARK: - Setup

    private func setupNotificationCategories() {
        // v0: plain notifications only — no action buttons.
        // Future: wire up Approve/Deny via file-based IPC for permission requests.
        let permissionCategory = UNNotificationCategory(
            identifier: permissionCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let finishedCategory = UNNotificationCategory(
            identifier: finishedCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            permissionCategory,
            finishedCategory
        ])
    }

    // MARK: - Permission Request

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            if granted {
                print("Notification permission granted")
            }
        }
    }

    // MARK: - Notifications

    func notifyPermissionNeeded(session: AgentSession) {
        // Debounce
        let notificationKey = "permission-\(session.id)"
        guard !recentNotifications.contains(notificationKey) else { return }
        recentNotifications.insert(notificationKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            self?.recentNotifications.remove(notificationKey)
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude needs your permission"
        content.subtitle = session.projectName
        content.body = session.notificationMessage ?? "Action required in \(session.projectName)"
        content.categoryIdentifier = permissionCategoryId
        content.userInfo = [
            "session_id": session.id,
            "action": "focus"
        ]

        // Use system sound
        if UserDefaults.standard.bool(forKey: "playSounds") != false {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("Funk.aiff"))
        }

        let request = UNNotificationRequest(
            identifier: notificationKey,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    func notifyAgentFinished(session: AgentSession) {
        // Debounce
        let notificationKey = "finished-\(session.id)"
        guard !recentNotifications.contains(notificationKey) else { return }
        recentNotifications.insert(notificationKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            self?.recentNotifications.remove(notificationKey)
        }

        let content = UNMutableNotificationContent()
        content.title = "Agent finished"
        content.subtitle = session.projectName
        if let tool = session.toolName, let act = session.activity {
            content.body = "Last: \(tool) \(act)"
        } else if let tool = session.toolName {
            content.body = "Last: \(tool)"
        } else {
            content.body = "Task completed in \(session.projectName)"
        }
        content.categoryIdentifier = finishedCategoryId
        content.userInfo = [
            "session_id": session.id,
            "action": "focus"
        ]

        // Use system sound
        if UserDefaults.standard.bool(forKey: "playSounds") != false {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("Hero.aiff"))
        }

        let request = UNNotificationRequest(
            identifier: notificationKey,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // v0: clicking the notification focuses the session
        if let sessionId = userInfo["session_id"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onNotificationClicked?(sessionId)
            }
        }

        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showControlPanel = Notification.Name("showControlPanel")
    static let focusSession = Notification.Name("focusSession")
}
