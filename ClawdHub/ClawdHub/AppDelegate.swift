//
//  AppDelegate.swift
//  ClawdHub
//
//  App lifecycle management and core service initialization
//

import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var statusDotLayer: CALayer?
    private var pulseAnimation: CABasicAnimation?

    var sessionManager: SessionManager!
    var hotkeyManager: HotkeyManager!
    var panelController: PanelController!
    var notificationManager: NotificationManager!
    var terminalFocusManager: TerminalFocusManager!
    var hookRegistrar: HookRegistrar!
    var onboardingController: OnboardingController?

    let appSettings = AppSettings()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupManagers()
        setupStatusItem()
        setupAnalytics()

        if !appSettings.hasCompletedOnboarding {
            showOnboarding()
        } else {
            setupHotkeys()
            registerHooks()
            requestNotificationPermission()
        }

        // Observe session changes to update menubar
        sessionManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    private func setupManagers() {
        sessionManager = SessionManager()
        hotkeyManager = HotkeyManager()
        panelController = PanelController(sessionManager: sessionManager, appSettings: appSettings)
        notificationManager = NotificationManager()
        terminalFocusManager = TerminalFocusManager()
        hookRegistrar = HookRegistrar()

        // Wire up panel controller callbacks
        panelController.onAgentSelected = { [weak self] session in
            self?.terminalFocusManager.focusTerminal(for: session)
        }

        // Wire up notification manager callbacks
        notificationManager.onNotificationClicked = { [weak self] sessionId in
            guard let session = self?.sessionManager.sessions.first(where: { $0.id == sessionId }) else { return }
            self?.terminalFocusManager.focusTerminal(for: session)
        }

        // Observe session changes for notifications
        sessionManager.onSessionNeedsAttention = { [weak self] session in
            guard let self = self, self.appSettings.notifyOnPermission else { return }
            self.notificationManager.notifyPermissionNeeded(session: session)
        }

        sessionManager.onSessionFinished = { [weak self] session in
            guard let self = self, self.appSettings.notifyOnFinish else { return }
            self.notificationManager.notifyAgentFinished(session: session)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol for the icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "ClawdHub") {
                let configuredImage = image.withSymbolConfiguration(config)
                button.image = configuredImage
                button.image?.isTemplate = true
            }

            // Handle clicks
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Add status dot layer
            setupStatusDot(in: button)
        }

        updateStatusItemAppearance()
    }

    private func setupStatusDot(in button: NSStatusBarButton) {
        let dotSize: CGFloat = 6
        let dotLayer = CALayer()
        dotLayer.frame = CGRect(
            x: button.bounds.width - dotSize - 2,
            y: 2,
            width: dotSize,
            height: dotSize
        )
        dotLayer.cornerRadius = dotSize / 2
        dotLayer.backgroundColor = NSColor.systemGray.cgColor

        button.wantsLayer = true
        button.layer?.addSublayer(dotLayer)

        self.statusDotLayer = dotLayer
    }

    private func setupHotkeys() {
        hotkeyManager.onPeekStart = { [weak self] in
            guard let self = self else { return }
            // Don't override persistent mode with peek mode
            if !self.panelController.isPersistent {
                self.panelController.showPanel(peek: true)
            }
            AnalyticsManager.shared.track("hotkey_peek", properties: [
                "session_count": self.sessionManager.sessions.count
            ])
        }

        hotkeyManager.onPeekEnd = { [weak self] in
            guard let self = self else { return }
            if !self.panelController.isPersistent {
                self.panelController.hidePanel()
            }
        }

        hotkeyManager.onPersist = { [weak self] in
            self?.panelController.showPanel(peek: false)
        }

        hotkeyManager.onCycleForward = { [weak self] index in
            self?.panelController.cycleSelection(to: index)
        }

        hotkeyManager.onReleaseWithSelection = { [weak self] _ in
            guard let self = self else { return }
            // Track before confirmSelection clears the index
            if let idx = self.panelController.selectedIndex,
               idx >= 1, idx <= self.sessionManager.sortedSessions.count {
                let session = self.sessionManager.sortedSessions[idx - 1]
                AnalyticsManager.shared.track("hotkey_open", properties: [
                    "terminal": session.terminalDisplayName,
                    "agent_status": "\(session.status)"
                ])
            }
            self.panelController.confirmSelection()
        }

        hotkeyManager.onNumberPressed = { [weak self] number in
            // Only fires when not peeking (persistent mode only)
            self?.panelController.selectAgent(at: number)
        }

        hotkeyManager.onEscapePressed = { [weak self] in
            self?.panelController.hidePanel()
        }

        hotkeyManager.isPanelVisible = { [weak self] in
            self?.panelController.isPersistent == true
        }

        hotkeyManager.start()
    }

    private func setupAnalytics() {
        AnalyticsManager.shared.configure(enabled: appSettings.telemetryEnabled)
        AnalyticsManager.shared.track("app_launched")
    }

    private func registerHooks() {
        hookRegistrar.registerHooksIfNeeded()
    }

    private func requestNotificationPermission() {
        notificationManager.requestPermission()
    }

    private func showOnboarding() {
        let controller = OnboardingController()
        controller.onComplete = { [weak self] in
            guard let self = self else { return }
            self.appSettings.hasCompletedOnboarding = true
            self.setupHotkeys()
            self.registerHooks()
            self.requestNotificationPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onboardingController = nil
            }
        }
        controller.showOnboarding(
            appSettings: appSettings,
            hookRegistrar: hookRegistrar,
            hotkeyManager: hotkeyManager,
            panelController: panelController,
            sessionManager: sessionManager
        )
        onboardingController = controller
    }

    // MARK: - Status Item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            panelController.showPanel(peek: false)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open Control Panel", action: #selector(openControlPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ClawdHub", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openControlPanel() {
        panelController.showPanel(peek: false)
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Status Updates

    private func updateStatusItemAppearance() {
        let sessions = sessionManager.sessions
        let needsAttention = sessions.filter { $0.status == .waitingInput }
        let hasError = sessions.contains { $0.status == .error }
        let hasRunning = sessions.contains { $0.status == .running }
        let hasIdle = sessions.contains { $0.status == .idle }

        // Update dot color and animation
        // Priority: error > waiting > running > idle > gray (no sessions)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let dotLayer = self.statusDotLayer else { return }

            if hasError {
                dotLayer.backgroundColor = NSColor.systemRed.cgColor
                self.stopPulseAnimation()
            } else if !needsAttention.isEmpty {
                dotLayer.backgroundColor = NSColor.systemOrange.cgColor
                self.startPulseAnimation()
            } else if hasRunning {
                dotLayer.backgroundColor = NSColor.systemYellow.cgColor
                self.stopPulseAnimation()
            } else if hasIdle {
                dotLayer.backgroundColor = NSColor.systemGreen.cgColor
                self.stopPulseAnimation()
            } else {
                dotLayer.backgroundColor = NSColor.systemGray.cgColor
                self.stopPulseAnimation()
            }
        }
    }

    private func startPulseAnimation() {
        guard pulseAnimation == nil else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 0.8
        animation.autoreverses = true
        animation.repeatCount = .infinity

        statusDotLayer?.add(animation, forKey: "pulse")
        pulseAnimation = animation
    }

    private func stopPulseAnimation() {
        statusDotLayer?.removeAnimation(forKey: "pulse")
        pulseAnimation = nil
    }
}

import Combine
