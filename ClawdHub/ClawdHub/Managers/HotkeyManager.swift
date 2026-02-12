//
//  HotkeyManager.swift
//  ClawdHub
//
//  Handles global hotkey monitoring for hold-to-peek and ⌘-tap cycling gestures
//

import Cocoa
import Carbon
import ApplicationServices

class HotkeyManager {

    // MARK: - Callbacks

    var onPeekStart: (() -> Void)?
    var onPeekEnd: (() -> Void)?
    var onPersist: (() -> Void)?
    var onCycleForward: ((Int) -> Void)?
    var onReleaseWithSelection: ((Int) -> Void)?
    var onNumberPressed: ((Int) -> Void)?
    var onEscapePressed: (() -> Void)?
    var isPanelVisible: (() -> Bool)?

    // MARK: - Private Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var previousFlags: NSEvent.ModifierFlags = []
    private var isOptionHeld = false
    private var isCommandHeld = false
    private var isPeeking = false
    private var peekStartTime: Date?
    private var commandTapCount = 0
    private var escapePressedDuringPeek = false
    private var safetyTimer: Timer?

    // Debouncing (keyDown only)
    private var lastKeyDownTime: Date?
    private let keyDownDebounceInterval: TimeInterval = 0.016 // ~60fps

    // MARK: - Public Methods

    func start() {
        startGlobalMonitor()
        startLocalMonitor()
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        cancelSafetyTimer()
    }

    // MARK: - Global Monitor (for events outside our app)

    private func startGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    // MARK: - Local Monitor (for events inside our app)

    private func startLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            // No debounce for flagsChanged — critical for detecting fast ⌘ taps
            handleModifierChange(event)
        case .keyDown:
            // Debounce only keyDown events
            let now = Date()
            if let lastTime = lastKeyDownTime, now.timeIntervalSince(lastTime) < keyDownDebounceInterval {
                return
            }
            lastKeyDownTime = now
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleModifierChange(_ event: NSEvent) {
        let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let wasOption = previousFlags.contains(.option)
        let wasCommand = previousFlags.contains(.command)
        let nowOption = currentFlags.contains(.option)
        let nowCommand = currentFlags.contains(.command)

        previousFlags = currentFlags

        let wasBoth = wasOption && wasCommand
        let nowBoth = nowOption && nowCommand

        // Both keys now held
        if !wasBoth && nowBoth {
            if !isPeeking {
                // First time both held → start peek
                isPeeking = true
                peekStartTime = Date()
                commandTapCount = 0
                escapePressedDuringPeek = false
                startSafetyTimer()
                DispatchQueue.main.async { [weak self] in
                    self?.onPeekStart?()
                }
            } else {
                // Already peeking, ⌘ pressed again → cycle forward
                commandTapCount += 1
                let count = commandTapCount
                DispatchQueue.main.async { [weak self] in
                    self?.onCycleForward?(count)
                }
            }
        }
        // ⌥ released → end peek
        else if isPeeking && !nowOption {
            endPeek()
        }
        // All other transitions (⌘ release during peek, etc.) are no-ops

        isOptionHeld = nowOption
        isCommandHeld = nowCommand
    }

    private func endPeek() {
        guard isPeeking else { return }
        isPeeking = false
        cancelSafetyTimer()

        if escapePressedDuringPeek {
            // User pressed Esc — dismiss without action
            DispatchQueue.main.async { [weak self] in
                self?.onPeekEnd?()
            }
        } else if commandTapCount > 0 {
            // User cycled to a selection — open it
            let count = commandTapCount
            DispatchQueue.main.async { [weak self] in
                self?.onReleaseWithSelection?(count)
            }
        } else if let start = peekStartTime, Date().timeIntervalSince(start) > 1.0 {
            // Held for >1s without cycling — persistent mode
            DispatchQueue.main.async { [weak self] in
                self?.onPersist?()
            }
        } else {
            // Quick peek, no selection — dismiss
            DispatchQueue.main.async { [weak self] in
                self?.onPeekEnd?()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Handle Escape key during peek
        if event.keyCode == kVK_Escape {
            if isPeeking {
                escapePressedDuringPeek = true
            }
            DispatchQueue.main.async { [weak self] in
                self?.onEscapePressed?()
            }
            return
        }

        // Handle number keys 1-9 (only when panel is visible and not during peek)
        guard !isPeeking,
              isPanelVisible?() == true,
              let characters = event.charactersIgnoringModifiers,
              let char = characters.first,
              let number = Int(String(char)),
              number >= 1 && number <= 9 else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onNumberPressed?(number)
        }
    }

    // MARK: - Safety Timer

    private func startSafetyTimer() {
        cancelSafetyTimer()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isPeeking else { return }
            // Check actual key state as ground truth
            // Only check Option — Command may be legitimately released between cycle taps
            let actualFlags = CGEventSource.flagsState(.combinedSessionState)
            let optionHeld = actualFlags.contains(.maskAlternate)
            if !optionHeld {
                // Option isn't actually held — force end peek
                self.endPeek()
            }
        }
    }

    private func cancelSafetyTimer() {
        safetyTimer?.invalidate()
        safetyTimer = nil
    }
}

// MARK: - Virtual Key Codes

private let kVK_Escape: UInt16 = 0x35
