//
//  OverlayView.swift
//  ClawdHub
//
//  Main floating panel SwiftUI view — landscape grid layout
//

import SwiftUI

struct OverlayView: View {
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var panelController: PanelController
    @EnvironmentObject var appSettings: AppSettings

    let onAgentSelected: (AgentSession) -> Void
    let onDismiss: () -> Void

    @State private var hoveredSessionId: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            // Near-opaque dark backing — Raycast-style readability over any wallpaper
            Color(red: 0.12, green: 0.12, blue: 0.14)
                .opacity(0.96)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider()
                    .opacity(0.5)

                // Agent grid or empty state
                if sessionManager.sortedSessions.isEmpty {
                    emptyStateView
                } else {
                    agentGridView
                }

                Divider()
                    .opacity(0.5)

                // Footer
                footerView
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 800, height: 580)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("ClawdHub")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // Attention badge
            if sessionManager.attentionCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(sessionManager.attentionCount) waiting")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Agent Grid

    private var agentGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(sessionManager.sortedSessions.enumerated()), id: \.element.id) { index, session in
                    AgentCardView(
                        session: session,
                        index: index + 1,
                        isHovered: hoveredSessionId == session.id,
                        isSelected: panelController.selectedIndex == index + 1,
                        onSelect: {
                            onAgentSelected(session)
                        }
                    )
                    .onHover { isHovered in
                        hoveredSessionId = isHovered ? session.id : nil
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.35))

            Text("No Active Agents")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Text("Start a new Claude Code session in your terminal\nand it will appear here automatically.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)

            Text("Sessions started before ClawdHub was installed won't appear.\nRestart them to pick up monitoring.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if panelController.isPersistent {
                Text("Click or 1-9 to select")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("\u{2318} to cycle \u{2022} Release to open")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Text("Esc to close")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

#Preview {
    let sessionManager = SessionManager()
    let panelController = PanelController(sessionManager: sessionManager, appSettings: AppSettings())

    return OverlayView(
        sessionManager: sessionManager,
        panelController: panelController,
        onAgentSelected: { _ in },
        onDismiss: {}
    )
    .environmentObject(AppSettings())
}
