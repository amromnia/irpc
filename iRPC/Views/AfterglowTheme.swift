import SwiftUI
import UIKit

extension Color {
    init(afterglowHex: String) {
        let value = UInt32(afterglowHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0xE44950
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }

    var afterglowHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "E44950" }
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct AfterglowMark: View {
    var color: Color = .white
    var body: some View {
        HStack(spacing: 5) {
            Capsule().frame(width: 7, height: 18)
            Capsule().frame(width: 7, height: 34)
            Capsule().frame(width: 7, height: 25)
            Circle().frame(width: 8, height: 8)
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}

struct AfterglowGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    func body(content: Content) -> some View {
        if reducedTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 30))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 30))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
        }
    }
}

struct SharingButton: View {
    let sharing: Bool
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        // The surrounding dock supplies Liquid Glass; keep one material layer
        // and a solid, high-contrast action within it.
        button.buttonStyle(.borderedProminent)
    }
    private var button: some View {
        Button(action: action) {
            Label(sharing ? "Stop sharing" : "Start sharing", systemImage: sharing ? "stop.fill" : "antenna.radiowaves.left.and.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .disabled(disabled)
        .buttonBorderShape(.capsule)
        .accessibilityHint(sharing ? "Clears presence on both Discord accounts" : "Shares your Music playback to selected accounts")
    }
}
