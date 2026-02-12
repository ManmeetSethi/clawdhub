//
//  OnboardingController.swift
//  ClawdHub
//
//  NSWindow management for the onboarding wizard + interactive tutorial lifecycle
//

import Cocoa
import SwiftUI

// MARK: - Tutorial Phase

enum TutorialPhase {
    case notStarted

    // Phase 1: Peek
    case peekPrompt          // Fingers: idle. "Hold ⌥ then press ⌘"
    case peekHolding         // Fingers: ⌥⌘ held. "That's Peek! Release when ready"
    case peekReleased        // Fingers: idle. "Nice! Hold ⌥⌘ again"
    case peekAgainHolding    // Fingers: ⌥⌘ held. "You've got Peek! Release to continue"

    // Phase 2: Cycle
    case cyclePrompt         // Fingers: idle. "Hold ⌥ then press ⌘" (opens panel)
    case cycleActive         // Fingers: ⌥⌘ held. "Now tap ⌘ — watch the highlight" + dots
    case cycleComplete       // Fingers: ⌥ held. "That's Cycle! Release to continue"
    case cycleReleased       // Fingers: idle. "Now let's learn to Open"

    // Phase 3: Open
    case openPrompt          // Fingers: idle. First attempt.
    case openResult          // First open done. Animation on right. "Once more!"
    case openComplete        // Second open done. Confetti. Next button.

    case persistTip
    case completed
}

// MARK: - Controller

class OnboardingController: NSObject, ObservableObject, NSWindowDelegate {

    // MARK: - Published State

    @Published var tutorialPhase: TutorialPhase = .notStarted

    // Option-only detection for tutorial feedback
    @Published var optionHeld = false

    // Cycle progress
    @Published var cycleTapCount: Int = 0
    let cycleTapsRequired: Int = 5

    // Hold reinforcement — shown when user releases ⌘ but keeps ⌥
    @Published var showHoldNudge = false

    // Preview state for inline tutorial panel
    @Published var previewVisible = false
    @Published var previewSelectedIndex: Int? = nil
    @Published var previewOpenedIndex: Int? = nil
    @Published var openedAgentName: String? = nil

    // MARK: - Properties

    private var window: NSWindow?
    private var tutorialLocalFlagsMonitor: Any?
    private var tutorialGlobalFlagsMonitor: Any?
    private var commandHeld = false
    let permissionManager = PermissionManager()
    var onComplete: (() -> Void)?

    private var hotkeyManager: HotkeyManager?
    private var panelController: PanelController?
    private var sessionManager: SessionManager?

    // Saved callbacks to restore after tutorial
    private var savedOnPeekStart: (() -> Void)?
    private var savedOnPeekEnd: (() -> Void)?
    private var savedOnPersist: (() -> Void)?
    private var savedOnCycleForward: ((Int) -> Void)?
    private var savedOnReleaseWithSelection: ((Int) -> Void)?
    private var savedOnNumberPressed: ((Int) -> Void)?
    private var savedOnEscapePressed: (() -> Void)?

    // MARK: - Demo Sessions

    static let demoSessions: [AgentSession] = [
        AgentSession(
            id: "demo-1",
            status: .running,
            cwd: "/Users/demo/projects/web-app",
            tty: "/dev/ttys000",
            terminal: "iTerm2",
            startedAt: Date().addingTimeInterval(-300),
            updatedAt: Date().addingTimeInterval(-10),
            toolName: "Edit",
            activity: "src/App.tsx",
            notificationMessage: nil
        ),
        AgentSession(
            id: "demo-2",
            status: .waitingInput,
            cwd: "/Users/demo/projects/api-server",
            tty: "/dev/ttys001",
            terminal: "Terminal",
            startedAt: Date().addingTimeInterval(-600),
            updatedAt: Date().addingTimeInterval(-5),
            toolName: nil,
            activity: nil,
            notificationMessage: "Permission needed to run tests"
        ),
        AgentSession(
            id: "demo-3",
            status: .idle,
            cwd: "/Users/demo/projects/docs",
            tty: "/dev/ttys002",
            terminal: "VS Code",
            startedAt: Date().addingTimeInterval(-900),
            updatedAt: Date().addingTimeInterval(-120),
            toolName: "Bash",
            activity: "npm run build",
            notificationMessage: nil
        )
    ]

    // MARK: - Window Management

    func showOnboarding(
        appSettings: AppSettings,
        hookRegistrar: HookRegistrar,
        hotkeyManager: HotkeyManager,
        panelController: PanelController,
        sessionManager: SessionManager
    ) {
        self.hotkeyManager = hotkeyManager
        self.panelController = panelController
        self.sessionManager = sessionManager

        let onboardingView = OnboardingView(
            permissionManager: permissionManager,
            onboardingController: self,
            hookRegistrar: hookRegistrar,
            onComplete: { [weak self] in
                self?.completeOnboarding()
            }
        )
        .environmentObject(appSettings)

        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.title = "Welcome to ClawdHub"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self

        // Non-resizable, no minimize/zoom
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Center on screen
        window.center()

        // Show
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func dismissOnboarding() {
        endTutorial()
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        endTutorial()
    }

    // MARK: - Tutorial Lifecycle

    func startTutorial() {
        guard let hotkeyManager = hotkeyManager,
              let sessionManager = sessionManager else { return }

        // Save existing callbacks
        savedOnPeekStart = hotkeyManager.onPeekStart
        savedOnPeekEnd = hotkeyManager.onPeekEnd
        savedOnPersist = hotkeyManager.onPersist
        savedOnCycleForward = hotkeyManager.onCycleForward
        savedOnReleaseWithSelection = hotkeyManager.onReleaseWithSelection
        savedOnNumberPressed = hotkeyManager.onNumberPressed
        savedOnEscapePressed = hotkeyManager.onEscapePressed

        // Inject demo sessions
        sessionManager.setDemoSessions(Self.demoSessions)

        // Reset state
        tutorialPhase = .peekPrompt
        optionHeld = false
        commandHeld = false
        showHoldNudge = false
        cycleTapCount = 0
        previewVisible = false
        previewSelectedIndex = nil
        previewOpenedIndex = nil
        openedAgentName = nil

        // Flags monitor: tracks both ⌥ and ⌘ independently.
        // This is the primary handler for holding-phase transitions because
        // HotkeyManager's persist mode (>1s hold) swallows onPeekEnd.
        let handleFlags: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hadBoth = self.optionHeld && self.commandHeld
            self.optionHeld = flags.contains(.option)
            self.commandHeld = flags.contains(.command)
            let hasBoth = self.optionHeld && self.commandHeld

            // Combo just broken — had both keys, now missing at least one
            guard hadBoth && !hasBoth else { return }

            switch self.tutorialPhase {
            case .peekHolding:
                // Always advance — staggered key releases (one key up a few ms
                // before the other) are physically normal and shouldn't block.
                self.previewVisible = false
                self.tutorialPhase = .peekReleased
            case .peekAgainHolding:
                // User already proved they know Peek — always advance.
                // Staggered key releases (one key up a few ms before the other)
                // are physically normal; don't penalize.
                self.previewVisible = false
                self.tutorialPhase = .cyclePrompt
            case .cycleActive:
                // Only reset if ⌥ was released (user abandoned the gesture).
                // ⌘ release alone is normal — user is tapping ⌘ to cycle.
                if !self.optionHeld {
                    self.previewVisible = false
                    self.tutorialPhase = .cyclePrompt
                }
            case .cycleComplete:
                // Same as peekAgainHolding: always advance on any release.
                // Go to cycleReleased (not openPrompt) so the first open
                // isn't accidentally triggered by this same release event.
                self.previewVisible = false
                self.tutorialPhase = .cycleReleased
            default:
                break
            }
        }
        tutorialLocalFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlags(event)
            return event
        }
        tutorialGlobalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            handleFlags(event)
        }

        // HotkeyManager callbacks — handle non-holding transitions.
        // Holding phase releases are handled by the flags monitor above.

        hotkeyManager.onPeekStart = { [weak self] in
            guard let self = self else { return }
            self.showHoldNudge = false
            self.previewVisible = true
            self.previewSelectedIndex = nil
            self.previewOpenedIndex = nil

            switch self.tutorialPhase {
            case .peekPrompt:
                NSSound(named: "Tink")?.play()
                self.tutorialPhase = .peekHolding
            case .peekReleased:
                NSSound(named: "Tink")?.play()
                self.tutorialPhase = .peekAgainHolding
            case .cyclePrompt:
                self.tutorialPhase = .cycleActive
            case .cycleReleased:
                self.tutorialPhase = .openPrompt
            case .openPrompt, .openResult:
                break // Just show the preview
            default:
                break
            }
        }

        hotkeyManager.onPeekEnd = { [weak self] in
            guard let self = self else { return }
            self.previewVisible = false
            // Holding phases handled by flags monitor.
            // Only handle openPrompt/openResult here (open = release action).
            self.handleOpenRelease()
        }

        hotkeyManager.onCycleForward = { [weak self] (index: Int) in
            guard let self = self else { return }
            let count = Self.demoSessions.count
            guard count > 0 else { return }
            self.previewSelectedIndex = ((index - 1) % count) + 1

            if self.tutorialPhase == .cycleActive {
                self.cycleTapCount += 1
                if self.cycleTapCount >= self.cycleTapsRequired {
                    NSSound(named: "Tink")?.play()
                    self.tutorialPhase = .cycleComplete
                }
            }
        }

        hotkeyManager.onReleaseWithSelection = { [weak self] (index: Int) in
            guard let self = self else { return }

            switch self.tutorialPhase {
            case .cycleActive:
                self.previewVisible = false
                self.tutorialPhase = .cyclePrompt
            case .cycleComplete:
                self.previewVisible = false
                self.tutorialPhase = .cycleReleased
            case .openPrompt, .openResult:
                self.handleOpenRelease()
            default:
                break
            }
        }

        hotkeyManager.onPersist = { [weak self] in
            self?.previewVisible = true
        }

        hotkeyManager.onEscapePressed = { [weak self] in
            self?.previewVisible = false
        }

        hotkeyManager.onNumberPressed = { (_: Int) in }

        // Start listening
        hotkeyManager.start()
    }

    /// Handles the open gesture completion (release after cycling).
    /// First open → openResult ("once more"). Second open → openComplete (confetti).
    private func handleOpenRelease() {
        guard tutorialPhase == .openPrompt || tutorialPhase == .openResult else { return }

        // Resolve which agent was selected
        if let idx = previewSelectedIndex, idx >= 1, idx <= Self.demoSessions.count {
            openedAgentName = Self.demoSessions[idx - 1].projectName
        }
        previewOpenedIndex = previewSelectedIndex
        NSSound(named: "Hero")?.play()

        if tutorialPhase == .openPrompt {
            // First open → show result, then prompt "once more"
            tutorialPhase = .openResult
            // Keep preview visible briefly to show the opened card animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.tutorialPhase == .openResult else { return }
                self.previewOpenedIndex = nil
                self.previewVisible = false
            }
        } else {
            // Second open → complete with confetti, no auto-advance
            tutorialPhase = .openComplete
        }
    }

    func endTutorial() {
        guard let hotkeyManager = hotkeyManager,
              let sessionManager = sessionManager else { return }

        guard tutorialPhase != .notStarted else { return }

        // Clean up tutorial flags monitors
        if let monitor = tutorialLocalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            tutorialLocalFlagsMonitor = nil
        }
        if let monitor = tutorialGlobalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            tutorialGlobalFlagsMonitor = nil
        }

        panelController?.hidePanel()
        sessionManager.clearDemoSessions()
        hotkeyManager.stop()

        hotkeyManager.onPeekStart = savedOnPeekStart
        hotkeyManager.onPeekEnd = savedOnPeekEnd
        hotkeyManager.onPersist = savedOnPersist
        hotkeyManager.onCycleForward = savedOnCycleForward
        hotkeyManager.onReleaseWithSelection = savedOnReleaseWithSelection
        hotkeyManager.onNumberPressed = savedOnNumberPressed
        hotkeyManager.onEscapePressed = savedOnEscapePressed

        tutorialPhase = .notStarted
        optionHeld = false
        commandHeld = false
        showHoldNudge = false
        cycleTapCount = 0
        previewVisible = false
        previewSelectedIndex = nil
        previewOpenedIndex = nil
        openedAgentName = nil
    }

    // MARK: - Completion

    private func completeOnboarding() {
        endTutorial()
        permissionManager.stopPollingAccessibility()
        DispatchQueue.main.async { [self] in
            self.window?.delegate = nil
            self.window?.close()
            self.window = nil
            self.onComplete?()
        }
    }
}
