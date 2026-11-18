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
    var darkVaporTint: Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha),
              saturation > 0.1 else { return Color(afterglowHex: "971B2B") }
        return Color(hue: Double(hue), saturation: Double(max(0.6, saturation)), brightness: Double(min(0.6, brightness)))
    }

}
