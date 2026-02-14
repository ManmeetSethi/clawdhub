//
//  PanelController.swift
//  ClawdHub
//
//  Controls the floating overlay panel
//

import Cocoa
import SwiftUI

class PanelController: ObservableObject {

    // MARK: - Published State

    @Published var isPeekMode = false
    @Published var isPersistent = false
    @Published var selectedIndex: Int? = nil

    // MARK: - Callbacks

    var onAgentSelected: ((AgentSession) -> Void)?

    // MARK: - Properties

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var clickOutsideMonitor: Any?

    private let sessionManager: SessionManager
    private let appSettings: AppSettings

    // MARK: - Initialization

    init(sessionManager: SessionManager, appSettings: AppSettings) {
        self.sessionManager = sessionManager
        self.appSettings = appSettings
    }

    // MARK: - Panel Management

    func showPanel(peek: Bool) {
        if panel == nil {
            createPanel()
        }

        isPeekMode = peek
        isPersistent = !peek
        selectedIndex = nil

        // Animate in
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1.0
        }

        // Setup click outside monitor for persistent mode
        if !peek {
            setupClickOutsideMonitor()
        }
    }

    func hidePanel(completion: (() -> Void)? = nil) {
        guard let panel = panel else {
            completion?()
            return
        }

        removeClickOutsideMonitor()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.isPeekMode = false
            self?.isPersistent = false
            completion?()
        })
    }

    func cycleSelection(to index: Int) {
        let count = sessionManager.sortedSessions.count
        guard count > 0 else { return }
        selectedIndex = ((index - 1) % count) + 1
    }

    func confirmSelection() {
        guard let idx = selectedIndex else {
            print("[PanelController] confirmSelection — no selectedIndex, hiding panel")
            hidePanel()
            return
        }
        print("[PanelController] confirmSelection — selectedIndex: \(idx)")
        selectAgent(at: idx)
    }

    func selectAgent(at index: Int) {
        let sortedSessions = sessionManager.sortedSessions
        guard index >= 1 && index <= sortedSessions.count else { return }

        let session = sortedSessions[index - 1]
        print("[PanelController] selectAgent — index: \(index), session: \(session.id), terminal: \(session.terminal)")
        // Hide panel and wait for orderOut to complete before activating terminal.
        // orderOut restores the focus stack, so activating before it fires gets undone.
        hidePanel { [weak self] in
            self?.onAgentSelected?(session)
        }
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let panelWidth: CGFloat = 800
        let panelHeight: CGFloat = 580

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Center on screen (upper third)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
            let y = screenFrame.origin.y + screenFrame.height * 0.65
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Create SwiftUI content
        let overlayView = OverlayView(
            sessionManager: sessionManager,
            panelController: self,
            onAgentSelected: { [weak self] session in
                guard let self = self else { return }
                if self.isPeekMode { return }  // Block clicks during peek
                // Hide panel and wait for orderOut before activating terminal
                self.hidePanel {
                    self.onAgentSelected?(session)
                }
            },
            onDismiss: { [weak self] in
                self?.hidePanel()
            }
        )
        .environmentObject(appSettings)

        let hostingView = NSHostingView(rootView: AnyView(overlayView))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    // MARK: - Click Outside Monitor

    private func setupClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }

            // Check if click is outside the panel
            let panelFrame = panel.frame

            // Convert click location to screen coordinates
            let screenLocation = NSEvent.mouseLocation

            if !panelFrame.contains(screenLocation) {
                DispatchQueue.main.async {
                    self.hidePanel()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
