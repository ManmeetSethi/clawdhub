//
//  PermissionManager.swift
//  ClawdHub
//
//  Checks and requests Accessibility + Notification permissions
//

import Foundation
import AppKit
import UserNotifications

class PermissionManager: ObservableObject {

    // MARK: - Published State

    @Published var isAccessibilityGranted = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Properties

    private var pollingTimer: Timer?
    private var notificationPollingTimer: Timer?
    private var hasResetTCC = false

    // MARK: - Accessibility

    func checkAccessibility() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    func startPollingAccessibility() {
        checkAccessibility()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isAccessibilityGranted = AXIsProcessTrusted()
            }
        }
    }

    func stopPollingAccessibility() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func openAccessibilitySettings() {
        // Clear stale TCC entries once per launch so a fresh entry is created
        // matching the current binary's ad-hoc signature.
        if !hasResetTCC {
            hasResetTCC = true
            if let bundleId = Bundle.main.bundleIdentifier {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", "Accessibility", bundleId]
                try? process.run()
                process.waitUntilExit()
            }
        }
        // Show the system dialog. The user clicks its "Open System Settings"
        // button, which both registers the app in the Accessibility list AND
        // opens System Settings to the right pane. We don't open Settings
        // ourselves — the dialog's button is what makes the app appear.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Notifications

    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func startPollingNotifications() {
        checkNotificationStatus()
        notificationPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkNotificationStatus()
        }
    }

    func stopPollingNotifications() {
        notificationPollingTimer?.invalidate()
        notificationPollingTimer = nil
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self?.notificationStatus = .authorized
                } else {
                    self?.checkNotificationStatus()
                }
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Cleanup

    deinit {
        stopPollingAccessibility()
        stopPollingNotifications()
    }
}
