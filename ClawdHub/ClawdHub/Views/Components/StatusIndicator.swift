//
//  StatusIndicator.swift
//  ClawdHub
//
//  Status dot indicator component
//

import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus
    var size: CGFloat = 8
    var showPulse: Bool = true

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .opacity(shouldPulse && isPulsing ? 0.5 : 1.0)
            .animation(
                shouldPulse ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if shouldPulse {
                    isPulsing = true
                }
            }
            .onChange(of: status) { newStatus in
                isPulsing = newStatus == .waitingInput && showPulse
            }
    }

    private var shouldPulse: Bool {
        return status == .waitingInput && showPulse
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        VStack {
            StatusIndicator(status: .running)
            Text("Running")
        }
        VStack {
            StatusIndicator(status: .waitingInput)
            Text("Waiting")
        }
        VStack {
            StatusIndicator(status: .idle)
            Text("Done")
        }
        VStack {
            StatusIndicator(status: .error)
            Text("Error")
        }
    }
    .padding()
}
