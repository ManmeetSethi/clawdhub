//
//  AgentStatus.swift
//  ClawdHub
//
//  Agent session status enumeration
//

import Foundation
import SwiftUI

enum AgentStatus: String, Codable, Equatable {
    case running = "running"
    case waitingInput = "waiting_input"
    case idle = "idle"
    case error = "error"

    var displayName: String {
        switch self {
        case .running:
            return "Running"
        case .waitingInput:
            return "Waiting"
        case .idle:
            return "Done"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .running:
            return .yellow
        case .waitingInput:
            return .orange
        case .idle:
            return .green
        case .error:
            return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .running:
            return .systemYellow
        case .waitingInput:
            return .systemOrange
        case .idle:
            return .systemGreen
        case .error:
            return .systemRed
        }
    }
}
