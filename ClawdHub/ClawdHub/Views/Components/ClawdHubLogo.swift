//
//  ClawdHubLogo.swift
//  ClawdHub
//
//  Two-part wordmark: "Clawd" white + "Hub" black-on-orange pill
//

import SwiftUI

struct ClawdHubLogo: View {
    enum Size {
        case small   // 16pt — panel headers
        case medium  // 24pt — about
        case large   // 48pt — welcome splash

        var fontSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 24
            case .large: return 48
            }
        }

        var pillPaddingH: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 10
            }
        }

        var pillPaddingV: CGFloat {
            switch self {
            case .small: return 1
            case .medium: return 2
            case .large: return 4
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 10
            }
        }
    }

    var size: Size = .large

    // Animation control — when true, each half is visible
    var showClawd: Bool = true
    var showHub: Bool = true

    private let phOrange = Color(red: 249/255, green: 152/255, blue: 39/255)

    var body: some View {
        HStack(spacing: 0) {
            Text("Clawd")
                .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .opacity(showClawd ? 1.0 : 0.0)
                .offset(x: showClawd ? 0 : -20)

            Text("Hub")
                .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, size.pillPaddingH)
                .padding(.vertical, size.pillPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .fill(phOrange)
                )
                .opacity(showHub ? 1.0 : 0.0)
                .offset(x: showHub ? 0 : 20)
        }
    }
}

struct ClawdHubLogo_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            ClawdHubLogo(size: .small)
            ClawdHubLogo(size: .medium)
            ClawdHubLogo(size: .large)
        }
        .padding(40)
        .background(Color(red: 0.106, green: 0.106, blue: 0.106))
    }
}
