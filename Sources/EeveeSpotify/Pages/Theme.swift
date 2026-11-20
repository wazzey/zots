import EeveeSpotifyC
import SwiftUI
import UIKit

enum Theme {
    static let spotifyGreen: Int = 0x1ED760
    static let launchAmoled = UserDefaults.amoled
    static let launchAccent = UserDefaults.accentRGB
    static let launchMonospace = UserDefaults.monospace
    static let launchLowercase = UserDefaults.lowercaseText
    static let launchSquare = UserDefaults.squareCorners
    static let launchScheme = UserDefaults.colorScheme

    static var accent: UIColor { color(accentOrGreen(launchAccent >= 0 ? launchAccent : launchScheme?.accent ?? -1)) }

    static func accentOrGreen(_ rgb: Int) -> Int { rgb >= 0 ? rgb : spotifyGreen }

    static func color(_ rgb: Int) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    static func rgb(of color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(round(min(max(r, 0), 1) * 255)) << 16) | (Int(round(min(max(g, 0), 1) * 255)) << 8) | Int(round(min(max(b, 0), 1) * 255))
    }
}

enum ThemeScheme: String, CaseIterable {
    case catppuccin, dracula, gruvbox, nord, rosePine, tokyoNight, midnight

    var title: String {
        switch self {
        case .catppuccin: return "Catppuccin"
        case .dracula: return "Dracula"
        case .gruvbox: return "Gruvbox"
        case .nord: return "Nord"
        case .rosePine: return "Rosé Pine"
        case .tokyoNight: return "Tokyo Night"
        case .midnight: return "Midnight"
        }
    }

    var base: Int {
        switch self {
        case .catppuccin: return 0x1E1E2E
        case .dracula: return 0x282A36
        case .gruvbox: return 0x282828
        case .nord: return 0x2E3440
        case .rosePine: return 0x191724
        case .tokyoNight: return 0x1A1B26
        case .midnight: return 0x0D0A1A
        }
    }

    var accent: Int {
        switch self {
        case .catppuccin: return 0xCBA6F7
        case .dracula: return 0xBD93F9
        case .gruvbox: return 0xFABD2F
        case .nord: return 0x88C0D0
        case .rosePine: return 0xEBBCBA
        case .tokyoNight: return 0x7AA2F7
        case .midnight: return 0xA78BFA
        }
    }
}

func activateTheme() {
    if Theme.launchMonospace || Theme.launchLowercase || Theme.launchSquare {
        eeveeLog("[EeveeSpotify][Theme] Text theme mono %d, lowercase %d, square %d, %d hooks", Theme.launchMonospace,
              Theme.launchLowercase, Theme.launchSquare,
              EeveeInstallTextTheme(Theme.launchMonospace, Theme.launchLowercase, Theme.launchSquare))
    }
    let scheme = Theme.launchScheme
    let base = scheme?.base ?? (Theme.launchAmoled ? 0x000000 : -1)
    let accent = Theme.launchAccent >= 0 ? Theme.launchAccent : scheme?.accent ?? -1
    guard base >= 0 || accent >= 0 else { return }
    let start = CFAbsoluteTimeGetCurrent()
    let swaps = EeveeInstallColorSwaps(base, scheme != nil, accent)
    eeveeLog("[EeveeSpotify][Theme] Base %@, accent %@, %d swaps (%.2f ms)",
          base >= 0 ? String(format: "#%06X", base) : "default",
          accent >= 0 ? String(format: "#%06X", accent) : "default", swaps,
          (CFAbsoluteTimeGetCurrent() - start) * 1000)
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        var grey = 0, green = 0, uiColor = 0
        EeveeColorSwapStats(&grey, &green, &uiColor)
        eeveeLog("[EeveeSpotify][Theme] First 30 s: %d surfaces to base, %d layer greens and %d UIColor greens to accent", grey, green, uiColor)
    }
}

extension UserDefaults {
    static var amoled: Bool {
        get { container.bool(forKey: "eeveeAmoled") }
        set { container.set(newValue, forKey: "eeveeAmoled") }
    }

    static var monospace: Bool {
        get { container.bool(forKey: "eeveeMonospace") }
        set { container.set(newValue, forKey: "eeveeMonospace") }
    }

    static var lowercaseText: Bool {
        get { container.bool(forKey: "eeveeLowercase") }
        set { container.set(newValue, forKey: "eeveeLowercase") }
    }

    static var squareCorners: Bool {
        get { container.bool(forKey: "eeveeSquareCorners") }
        set { container.set(newValue, forKey: "eeveeSquareCorners") }
    }

    static var colorScheme: ThemeScheme? {
        get { container.string(forKey: "eeveeColorScheme").flatMap(ThemeScheme.init(rawValue:)) }
        set { container.set(newValue?.rawValue, forKey: "eeveeColorScheme") }
    }

    static var accentRGB: Int {
        get { container.object(forKey: "eeveeAccent") as? Int ?? -1 }
        set { newValue < 0 ? container.removeObject(forKey: "eeveeAccent") : container.set(newValue, forKey: "eeveeAccent") }
    }
}
