//
//  OnboardingView.swift
//  ClawdHub
//
//  7-step onboarding wizard for first launch
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var onboardingController: OnboardingController
    @EnvironmentObject var appSettings: AppSettings

    var hookRegistrar: HookRegistrar
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var hooksInstalled = false
    @State private var hookError: String?
    @State private var showClawd = false
    @State private var showHub = false
    @State private var logoPunch = false
    @State private var taglineVisible = false
    @State private var showGetStarted = false
    @State private var emailAddress = ""
    @State private var emailSubmitted = false

    // Brand colors
    private let phBlack = Color(red: 0.106, green: 0.106, blue: 0.106)
    private let phOrange = Color(red: 249/255, green: 152/255, blue: 39/255)

    private let totalSteps = 7

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: notificationStep
                case 3: hookSetupStep
                case 4: hotkeyTutorialStep
                case 5: emailCaptureStep
                case 6: readyStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .opacity(currentStep == 0 ? 0 : 0.3)

            // Navigation bar
            navigationBar
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(currentStep == 0 ? phBlack : Color.clear)
        }
        .frame(width: 750, height: 500)
        .background(VisualEffectView(material: .contentBackground, blendingMode: .behindWindow))
        .onAppear {
            permissionManager.startPollingAccessibility()
            permissionManager.startPollingNotifications()
            trackOnboardingStep(0)
        }
        .onDisappear {
            permissionManager.stopPollingAccessibility()
            permissionManager.stopPollingNotifications()
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Step indicator dots
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step == currentStep ? phOrange : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            // Back button — hide during tutorial, email step, and on step 0/last
            if currentStep > 0 && currentStep < totalSteps - 1 && !isTutorialActive && currentStep != 5 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            // Next / Get Started / Finish button
            if currentStep == 0 {
                // Button is inside welcomeStep content — nav bar empty for step 0
                EmptyView()
            } else if currentStep == totalSteps - 1 {
                orangeButton("Start Using ClawdHub") {
                    AnalyticsManager.shared.trackAlways("onboarding_completed")
                    onComplete()
                }
            } else if currentStep == 1 {
                orangeButton("Next", disabled: !permissionManager.isAccessibilityGranted) { advance() }
            } else if currentStep == 2 {
                orangeButton("Next", disabled: permissionManager.notificationStatus != .authorized) { advance() }
            } else if currentStep == 4 {
                if onboardingController.tutorialPhase == .openComplete
                    || onboardingController.tutorialPhase == .persistTip
                    || onboardingController.tutorialPhase == .completed {
                    orangeButton("Next") { advance() }
                }
            } else if currentStep == 5 {
                if emailSubmitted {
                    orangeButton("Next") { advance() }
                } else {
                    Button("Skip") {
                        AnalyticsManager.shared.trackAlways("onboarding_email_skipped")
                        advance()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    orangeButton("Submit", disabled: !isValidEmail) {
                        submitEmail()
                    }
                }
            } else {
                orangeButton("Next", disabled: !canAdvance) { advance() }
            }
        }
    }

    private var isTutorialActive: Bool {
        guard currentStep == 4 else { return false }
        switch onboardingController.tutorialPhase {
        case .notStarted, .openComplete, .persistTip, .completed:
            return false
        default:
            return true
        }
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 1: return permissionManager.isAccessibilityGranted
        case 2: return permissionManager.notificationStatus == .authorized
        case 3: return hooksInstalled
        default: return true
        }
    }

    private func advance() {
        if currentStep == 3 {
            // About to enter tutorial step — start tutorial
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStep = 4
            }
            onboardingController.startTutorial()
            trackOnboardingStep(4)
        } else {
            let nextStep = min(currentStep + 1, totalSteps - 1)
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStep = nextStep
            }
            trackOnboardingStep(nextStep)
        }
    }

    private func trackOnboardingStep(_ step: Int) {
        let stepNames = ["welcome", "accessibility", "notifications", "hooks", "tutorial", "email", "ready"]
        guard step < stepNames.count else { return }
        AnalyticsManager.shared.trackAlways("onboarding_\(stepNames[step])")
    }

    private func orangeButton(_ label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(disabled ? phOrange.opacity(0.4) : phOrange)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        ZStack {
            phBlack.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                ClawdHubLogo(size: .large, showClawd: showClawd, showHub: showHub)
                    .scaleEffect(logoPunch ? 1.08 : 1.0)

                Text("Monitor. Switch. Control.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.5))
                    .opacity(taglineVisible ? 1.0 : 0.0)

                if showGetStarted {
                    orangeButton("Get Started") { advance() }
                        .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            // Start sound immediately
            if let soundURL = Bundle.main.url(forResource: "intro", withExtension: "aiff") {
                NSSound(contentsOf: soundURL, byReference: true)?.play()
            }

            // 0.3s — "Clawd" slides in from left
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.6)) {
                    showClawd = true
                }
            }

            // 1.2s — "Hub" pill slams in from right
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    showHub = true
                }
            }

            // 2.5s — Punch scale on full logo
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                    logoPunch = true
                }
                // Settle back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        logoPunch = false
                    }
                }
            }

            // 3.2s — Tagline fades in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeOut(duration: 0.5)) {
                    taglineVisible = true
                }
            }

            // 4.5s — "Get Started" button appears (sound ends)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showGetStarted = true
                }
            }
        }
    }

    // MARK: - Step 2: Accessibility

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundColor(permissionManager.isAccessibilityGranted ? .green : phOrange)

            Text("Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("ClawdHub needs Accessibility access to detect the \u{2325}\u{2318} hotkey globally, so you can peek at your agents from anywhere.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .red)
                Text(permissionManager.isAccessibilityGranted ? "Permission granted" : "Permission not granted")
                    .font(.callout)
                    .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .secondary)
            }
            .padding(.vertical, 8)

            if !permissionManager.isAccessibilityGranted {
                orangeButton("Grant Access") {
                    permissionManager.openAccessibilitySettings()
                }

                VStack(alignment: .leading, spacing: 8) {
                    guideStep(number: 1, text: "Click \"Grant Access\" above")
                    guideStep(number: 2, text: "Click \"Open System Settings\" in the dialog")
                    guideStep(number: 3, text: "Find ClawdHub and toggle it on")
                }
                .padding(14)
                .background(phOrange.opacity(0.08))
                .cornerRadius(10)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 3: Notifications

    private var notificationStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: permissionManager.notificationStatus == .authorized ? "bell.badge.fill" : "bell.fill")
                .font(.system(size: 44))
                .foregroundColor(permissionManager.notificationStatus == .authorized ? .green : phOrange)

            Text("Notification Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Get notified when agents need your attention or finish their tasks.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if permissionManager.notificationStatus == .authorized {
                // Success state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Notifications enabled")
                        .font(.callout)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
            } else if permissionManager.notificationStatus == .notDetermined {
                // First request — show button that triggers the system dialog
                orangeButton("Allow Notifications") {
                    permissionManager.requestNotificationPermission()
                }
            } else {
                // Denied or provisional — guide user to System Settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enable notifications in System Settings:")
                        .font(.callout)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 8) {
                        guideStep(number: 1, text: "Click \"Open System Settings\" below")
                        guideStep(number: 2, text: "Find \"ClawdHub\" in the app list")
                        guideStep(number: 3, text: "Toggle \"Allow Notifications\" on")
                    }
                }
                .padding(14)
                .background(phOrange.opacity(0.08))
                .cornerRadius(10)

                orangeButton("Open System Settings") {
                    permissionManager.openNotificationSettings()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
        .onAppear {
            // Auto-trigger the system dialog if not yet asked
            if permissionManager.notificationStatus == .notDetermined {
                permissionManager.requestNotificationPermission()
            }
        }
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(phOrange))
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Step 4: Hook Setup

    private var hookSetupStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: hooksInstalled ? "checkmark.circle.fill" : "link.badge.plus")
                .font(.system(size: 44))
                .foregroundColor(hooksInstalled ? .green : phOrange)

            Text("Claude Code Hooks")
                .font(.title2)
                .fontWeight(.semibold)

            Text("ClawdHub installs small scripts that let Claude Code report its status. This modifies your Claude settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            // What gets modified
            VStack(alignment: .leading, spacing: 6) {
                Label("~/.claude/settings.json", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("~/.clawdhub/hooks/", systemImage: "folder")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            if hooksInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Hooks installed successfully")
                        .font(.callout)
                        .foregroundColor(.green)
                }
            } else {
                orangeButton("Install Hooks") {
                    hookRegistrar.registerHooksIfNeeded()
                    hooksInstalled = true
                }
            }

            if hooksInstalled {
                Text("Only new Claude Code sessions will be monitored. Restart any running sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 5: Hotkey Tutorial (Side-by-Side)

    private var hotkeyTutorialStep: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left side: instructions
                tutorialInstructions
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .opacity(0.3)

                // Right side: mini panel preview
                TutorialPanelPreview(
                    sessions: OnboardingController.demoSessions,
                    isVisible: onboardingController.previewVisible,
                    selectedIndex: onboardingController.previewSelectedIndex,
                    openedIndex: onboardingController.previewOpenedIndex,
                    openedAgentName: onboardingController.openedAgentName
                )
                .frame(width: 320)
            }

            // Confetti overlay for open celebration
            if onboardingController.tutorialPhase == .openComplete {
                ConfettiView()
            }
        }
    }

    private var tutorialInstructions: some View {
        VStack(spacing: 16) {
            // Step progress indicator (visible during active tutorial phases)
            if isTutorialActive {
                tutorialStepIndicator
                    .padding(.top, 20)
            }

            Spacer()

            Group {
                switch onboardingController.tutorialPhase {
                case .notStarted:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Starting tutorial...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                // MARK: Phase 1 — Peek

                case .peekPrompt:
                    // Fingers: idle
                    VStack(spacing: 16) {
                        Text("Hold \u{2325} then press \u{2318}")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("This brings up your agent panel")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            Text("then")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2318}")
                        }
                        .padding(.vertical, 4)

                        if onboardingController.showHoldNudge {
                            holdNudge
                        } else if onboardingController.optionHeld {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\u{2325} held — now press \u{2318}!")
                                    .fontWeight(.medium)
                            }
                            .font(.callout)
                            .foregroundColor(.green)
                            .transition(.opacity)
                        }
                    }

                case .peekHolding:
                    // Fingers: ⌥⌘ held, panel visible
                    VStack(spacing: 16) {
                        celebrationBadge("That's Peek!")

                        Text("You're seeing your agents")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        Text("Release both keys when ready")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                    }

                case .peekReleased:
                    // Fingers: idle, panel hidden
                    VStack(spacing: 16) {
                        Text("Nice! Let's do that once more")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Hold \u{2325}\u{2318} again")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            keyHintBadge("\u{2318}")
                        }
                        .padding(.vertical, 4)

                        if onboardingController.showHoldNudge {
                            holdNudge
                        }
                    }

                case .peekAgainHolding:
                    // Fingers: ⌥⌘ held, panel visible
                    VStack(spacing: 16) {
                        celebrationBadge("You've got Peek down!")

                        Text("Release both keys to continue")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                    }

                // MARK: Phase 2 — Cycle

                case .cyclePrompt:
                    // Fingers: idle — open the panel first
                    VStack(spacing: 16) {
                        Text("Hold \u{2325} then press \u{2318}")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Open the panel again")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            Text("then")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2318}")
                        }
                        .padding(.vertical, 4)

                        if onboardingController.optionHeld {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\u{2325} held — now press \u{2318}!")
                                    .fontWeight(.medium)
                            }
                            .font(.callout)
                            .foregroundColor(.green)
                            .transition(.opacity)
                        }
                    }

                case .cycleActive:
                    // Fingers: ⌥⌘ held, panel visible — tap ⌘ to cycle
                    VStack(spacing: 16) {
                        Text("Now tap \u{2318} again")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Watch the highlight move between agents")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        keyHint("\u{2318}", label: "Tap while holding \u{2325}")

                        cycleProgressDots
                    }

                case .cycleComplete:
                    // Fingers: ⌥ held, panel visible
                    VStack(spacing: 16) {
                        celebrationBadge("That's Cycle!")

                        Text("Release both keys to continue")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                    }

                case .cycleReleased:
                    // Fingers: idle — explain Open before starting
                    VStack(spacing: 16) {
                        Text("Now let's learn Open")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Cycle to an agent, then release \u{2325} to open it")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Hold \u{2325}\u{2318} to start")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            Text("then")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2318}")
                        }
                        .padding(.vertical, 4)

                        if onboardingController.optionHeld {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\u{2325} held — now press \u{2318}!")
                                    .fontWeight(.medium)
                            }
                            .font(.callout)
                            .foregroundColor(.green)
                            .transition(.opacity)
                        }
                    }

                // MARK: Phase 3 — Open

                case .openPrompt:
                    // Fingers: idle — first attempt
                    VStack(spacing: 16) {
                        Text("Hold \u{2325}, tap \u{2318} twice,\nthen release \u{2325}")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)

                        Text("Releasing \u{2325} opens the selected agent")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            Text("+")
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2318}\u{2318}")
                            Text("then release")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2325}")
                        }
                        .padding(.vertical, 4)
                    }

                case .openResult:
                    // First open done — animation on right, prompt once more
                    VStack(spacing: 16) {
                        celebrationBadge("Nice!")

                        Text("Let's do that once more")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.top, 4)

                        Text("Hold \u{2325}, tap \u{2318}, release \u{2325}")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            keyHintBadge("\u{2325}")
                            Text("+")
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2318}\u{2318}")
                            Text("then release")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            keyHintBadge("\u{2325}")
                        }
                        .padding(.vertical, 4)
                    }

                case .openComplete:
                    // Second open done — look at the right side
                    VStack(spacing: 16) {
                        celebrationBadge("You've mastered Open!")

                        Text("That's everything — you're ready")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                // MARK: Persist & Completed

                case .persistTip:
                    VStack(spacing: 16) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 36))
                            .foregroundColor(phOrange)

                        Text("Pro Tip: Persist Mode")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Hold \u{2325}\u{2318} for more than 1 second,\nthen release. The panel stays open\nso you can browse at your own pace.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(phOrange)
                            Text("You'll discover this naturally.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(phOrange.opacity(0.08))
                        .cornerRadius(8)
                    }

                case .completed:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)

                        Text("Tutorial Complete!")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }
            .id(onboardingController.tutorialPhase)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
            .animation(.easeInOut(duration: 0.4), value: onboardingController.tutorialPhase)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Tutorial Step Indicator

    // Steps map to groups of sub-phases: 1=Peek, 2=Cycle, 3=Open
    private var tutorialStepIndicator: some View {
        HStack(spacing: 0) {
            stepBadge(number: 1, label: "Peek", step: 1)
            stepConnector(step: 1)
            stepBadge(number: 2, label: "Cycle", step: 2)
            stepConnector(step: 2)
            stepBadge(number: 3, label: "Open", step: 3)
        }
        .padding(.horizontal, 8)
    }

    /// Which high-level step (1/2/3) the current sub-phase belongs to
    private var currentTutorialStep: Int {
        switch onboardingController.tutorialPhase {
        case .peekPrompt, .peekHolding, .peekReleased, .peekAgainHolding:
            return 1
        case .cyclePrompt, .cycleActive, .cycleComplete, .cycleReleased:
            return 2
        case .openPrompt, .openResult, .openComplete:
            return 3
        default:
            return 0
        }
    }

    private func stepIsComplete(_ step: Int) -> Bool {
        currentTutorialStep > step
            || [TutorialPhase.persistTip, .completed].contains(onboardingController.tutorialPhase)
    }

    private func stepIsCurrent(_ step: Int) -> Bool {
        currentTutorialStep == step
    }

    private func stepBadge(number: Int, label: String, step: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if stepIsComplete(step) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(phOrange)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(stepIsCurrent(step) ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(stepIsCurrent(step) ? phOrange : Color.secondary.opacity(0.2))
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: stepIsComplete(step))

            Text(label)
                .font(.caption2)
                .foregroundColor(stepIsCurrent(step) || stepIsComplete(step) ? .primary : .secondary)
        }
    }

    private func stepConnector(step: Int) -> some View {
        Rectangle()
            .fill(stepIsComplete(step) ? phOrange : Color.secondary.opacity(0.2))
            .frame(height: 2)
            .frame(maxWidth: 40)
            .padding(.horizontal, 4)
            .padding(.bottom, 16) // Align with circle, not label
            .animation(.easeInOut(duration: 0.3), value: stepIsComplete(step))
    }

    // MARK: - Cycle Progress Dots

    private var cycleProgressDots: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<onboardingController.cycleTapsRequired, id: \.self) { i in
                    Circle()
                        .fill(i < onboardingController.cycleTapCount ? phOrange : Color.secondary.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .scaleEffect(i < onboardingController.cycleTapCount ? 1.1 : 1.0)
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.5),
                            value: onboardingController.cycleTapCount
                        )
                }
            }
            Text("\(onboardingController.cycleTapCount)/\(onboardingController.cycleTapsRequired)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private var holdNudge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Keep holding both \u{2325} and \u{2318}!")
                .fontWeight(.medium)
        }
        .font(.callout)
        .foregroundColor(.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
        .transition(.opacity)
    }

    private func keyHintBadge(_ keys: String) -> some View {
        Text(keys)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
    }

    private func keyHint(_ keys: String, label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func celebrationBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text(text)
                .fontWeight(.medium)
        }
        .font(.callout)
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(phOrange)
        )
    }

    // MARK: - Step 6: Email Capture

    private var isValidEmail: Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return emailAddress.range(of: pattern, options: .regularExpression) != nil
    }

    private func submitEmail() {
        AnalyticsManager.shared.trackAnonymous("email_collected", properties: ["email": emailAddress])
        withAnimation(.easeInOut(duration: 0.3)) {
            emailSubmitted = true
        }
    }

    private var emailCaptureStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: emailSubmitted ? "envelope.open.fill" : "envelope.fill")
                .font(.system(size: 44))
                .foregroundColor(emailSubmitted ? .green : phOrange)

            Text("One Last Thing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("We're building support for more terminals, different coding agents, mobile notifications, and much more. Drop your email if you'd like early access to new features and a heads-up when we launch on Product Hunt — we'd love your support.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Text("No account needed — ClawdHub runs entirely on your Mac. Your email isn't linked to any usage data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if emailSubmitted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Thanks! We'll let you know.")
                        .font(.callout)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
            } else {
                TextField("your@email.com", text: $emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Only used for product updates and launch announcements. No spam, ever.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 7: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(phOrange)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("ClawdHub is ready to monitor your agents.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Summary
            VStack(alignment: .leading, spacing: 10) {
                summaryRow(
                    icon: "checkmark.shield",
                    label: "Accessibility",
                    granted: permissionManager.isAccessibilityGranted
                )
                summaryRow(
                    icon: "bell.badge",
                    label: "Notifications",
                    granted: permissionManager.notificationStatus == .authorized
                )
                summaryRow(
                    icon: "link",
                    label: "Hooks",
                    granted: hooksInstalled
                )
            }
            .padding(16)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(10)

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 20)

            // Options
            VStack(spacing: 12) {
                Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
                    .font(.callout)
                Toggle("Help improve ClawdHub with anonymous usage data", isOn: $appSettings.telemetryEnabled)
                    .font(.callout)
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func summaryRow(icon: String, label: String, granted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(granted ? phOrange : .secondary)
            Text(label)
                .font(.callout)
            Spacer()
            Text(granted ? "Configured" : "Skipped")
                .font(.caption)
                .foregroundColor(granted ? phOrange : .secondary)
        }
    }
}

// MARK: - Tutorial Panel Preview

struct TutorialPanelPreview: View {
    let sessions: [AgentSession]
    let isVisible: Bool
    let selectedIndex: Int?
    let openedIndex: Int?
    var openedAgentName: String? = nil

    private let phOrange = Color(red: 249/255, green: 152/255, blue: 39/255)

    var body: some View {
        ZStack {
            // Placeholder when not visible
            if !isVisible {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Panel preview")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Hold \u{2325}\u{2318} to see it appear")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }

            // Mini panel when visible
            if isVisible {
                VStack(spacing: 0) {
                    // Mini header
                    HStack {
                        Text("ClawdHub")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider().opacity(0.3)

                    // Session cards
                    VStack(spacing: 8) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                            previewCard(session: session, index: index + 1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().opacity(0.3)

                    // Mini footer
                    HStack {
                        Text("\u{2318} to cycle")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Spacer()
                        Text("Esc to close")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                )
                .padding(12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .animation(.easeInOut(duration: 0.15), value: selectedIndex)
        .animation(.easeInOut(duration: 0.15), value: openedIndex)
    }

    private func previewCard(session: AgentSession, index: Int) -> some View {
        let isSelected = selectedIndex == index
        let isOpened = openedIndex == index

        return HStack(spacing: 10) {
            // Index
            Text("\(index)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 16)

            // Status dot
            StatusIndicator(status: session.status, size: 6, showPulse: false)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let summary = session.activitySummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Terminal badge
            Text(session.terminalDisplayName)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(cardBackground(isSelected: isSelected, isOpened: isOpened))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOpened || isSelected ? phOrange : Color.clear, lineWidth: isOpened ? 2 : 1.5)
        )
        .overlay(
            // "Opening..." banner on the opened card
            Group {
                if isOpened, let name = openedAgentName {
                    VStack(spacing: 4) {
                        Text("Opening \(name)...")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(phOrange)
                            )
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isOpened)
        )
        .scaleEffect(isOpened ? 1.08 : isSelected ? 1.04 : 0.97)
        .opacity(isSelected || isOpened ? 1.0 : selectedIndex != nil ? 0.5 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOpened)
    }

    private func cardBackground(isSelected: Bool, isOpened: Bool) -> Color {
        if isOpened {
            return phOrange.opacity(0.25)
        } else if isSelected {
            return phOrange.opacity(0.08)
        }
        return Color.secondary.opacity(0.05)
    }
}
