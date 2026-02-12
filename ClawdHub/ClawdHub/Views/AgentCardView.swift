//
//  AgentCardView.swift
//  ClawdHub
//
//  Compact vertical agent session card for grid layout
//

import SwiftUI

struct AgentCardView: View {
    let session: AgentSession
    let index: Int
    let isHovered: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Top row: index, status, duration
                HStack {
                    Text("\(index)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        StatusIndicator(status: session.status, size: 6)
                        Text(session.status.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Text(session.duration)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer(minLength: 2)

                // Project name
                Text(session.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // Path
                Text(session.displayPath)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 2)

                // Activity summary
                if let summary = session.activitySummary {
                    Text(summary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(session.status == .waitingInput ? .orange : .white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

            }
            .padding(10)
            .frame(minHeight: 130)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.3) :
                  isHovered ? Color.white.opacity(0.15) :
                  Color.white.opacity(0.08))
    }

    @ViewBuilder
    private var cardBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
        } else if session.status == .waitingInput {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.6), lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.clear, lineWidth: 0)
        }
    }
}

// MARK: - Preview

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
        AgentCardView(
            session: AgentSession(
                id: "test1",
                status: .running,
                cwd: "/Users/dev/Code/myproject",
                tty: "/dev/ttys003",
                terminal: "iTerm2",
                startedAt: Date().addingTimeInterval(-150),
                updatedAt: Date(),
                toolName: "Bash",
                activity: "npm test"
            ),
            index: 1,
            isHovered: false,
            isSelected: false,
            onSelect: {}
        )

        AgentCardView(
            session: AgentSession(
                id: "test2",
                status: .waitingInput,
                cwd: "/Users/dev/Code/another-project",
                tty: "/dev/ttys007",
                terminal: "Terminal",
                startedAt: Date().addingTimeInterval(-3600),
                updatedAt: Date().addingTimeInterval(-60),
                notificationMessage: "Needs permission: Bash"
            ),
            index: 2,
            isHovered: true,
            isSelected: true,
            onSelect: {}
        )

        AgentCardView(
            session: AgentSession(
                id: "test3",
                status: .idle,
                cwd: "/Users/dev/Code/finished-project",
                tty: "/dev/ttys010",
                terminal: "Ghostty",
                startedAt: Date().addingTimeInterval(-7200),
                updatedAt: Date().addingTimeInterval(-120),
                toolName: "Edit",
                activity: "App.tsx"
            ),
            index: 3,
            isHovered: false,
            isSelected: false,
            onSelect: {}
        )

        AgentCardView(
            session: AgentSession(
                id: "test4",
                status: .error,
                cwd: "/Users/dev/Code/broken-project",
                tty: "/dev/ttys012",
                terminal: "Cursor",
                startedAt: Date().addingTimeInterval(-300),
                updatedAt: Date().addingTimeInterval(-30)
            ),
            index: 4,
            isHovered: false,
            isSelected: false,
            onSelect: {}
        )
    }
    .padding(20)
    .frame(width: 800)
    .background(Color.black.opacity(0.3))
}
