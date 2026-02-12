//
//  ConfettiView.swift
//  ClawdHub
//
//  Confetti particle overlay for tutorial celebrations
//

import SwiftUI

struct ConfettiView: View {
    @State private var animate = false

    private let pieces: [ConfettiPiece] = (0..<30).map { _ in
        ConfettiPiece(
            color: [Color.blue, .purple, .green, .orange, .pink, .yellow].randomElement()!,
            x: CGFloat.random(in: -150...150),
            y: CGFloat.random(in: 150...350),
            rotation: Double.random(in: -360...360),
            scale: CGFloat.random(in: 0.4...1.0)
        )
    }

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: 8 * piece.scale, height: 5 * piece.scale)
                    .offset(
                        x: animate ? piece.x : 0,
                        y: animate ? piece.y : -20
                    )
                    .rotationEffect(.degrees(animate ? piece.rotation : 0))
                    .opacity(animate ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 2.0)) {
                animate = true
            }
        }
    }
}

private struct ConfettiPiece {
    let color: Color
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let scale: CGFloat
}
