import AppKit

/// Colors taken from Omawrite, resolved live against the system appearance.
enum Theme {
    static let page = dynamic(light: 0xFFFFFF, dark: 0x101010)
    static let text = dynamic(light: 0x222324, dark: 0xEEEEEE)
    static let marker = dynamic(light: 0xAEB1B5, dark: 0x4F525A)
    static let muted = dynamic(light: 0xAEB1B5, dark: 0x909191)
    static let link = dynamic(light: 0x2077B2, dark: 0x5584AA)
    static let code = dynamic(light: 0xF3F3F3, dark: 0x1C1C1C)
    static let selection = dynamic(light: 0x2077B2, dark: 0x186A9A, lightAlpha: 0.22, darkAlpha: 0.55)

    private static func dynamic(light: UInt32, dark: UInt32,
                                lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? color(dark, darkAlpha) : color(light, lightAlpha)
        }
    }

    private static func color(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }
}

/// The writing font (IBM Plex Mono, bundled) in its four cuts, plus line spacing.
struct Fonts {
    static let defaultSize: CGFloat = 17
    static var size: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: "fontSize")
            return stored > 0 ? CGFloat(stored) : defaultSize
        }
        set { UserDefaults.standard.set(Double(min(40, max(10, newValue))), forKey: "fontSize") }
    }

    let regular: NSFont
    let bold: NSFont
    let italic: NSFont
    let boldItalic: NSFont
    let small: NSFont
    let paragraph: NSParagraphStyle

    init(size: CGFloat = Fonts.size) {
        let fallback = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        regular = NSFont(name: "IBMPlexMono", size: size) ?? fallback
        bold = NSFont(name: "IBMPlexMono-Bold", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        italic = NSFont(name: "IBMPlexMono-Italic", size: size)
            ?? NSFontManager.shared.convert(fallback, toHaveTrait: .italicFontMask)
        boldItalic = NSFont(name: "IBMPlexMono-BoldItalic", size: size)
            ?? NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        small = NSFont(name: "IBMPlexMono", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)

        // Omawrite sets lines at 140% of the font's natural height. Adding the
        // extra below each line keeps the caret its normal height.
        let style = NSMutableParagraphStyle()
        let natural = regular.ascender - regular.descender + regular.leading
        style.lineSpacing = (natural * 0.4).rounded()
        paragraph = style
    }

    func font(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
        switch (isBold, isItalic) {
        case (true, true): return boldItalic
        case (true, false): return bold
        case (false, true): return italic
        default: return regular
        }
    }

    func traits(of font: NSFont) -> (bold: Bool, italic: Bool) {
        let t = font.fontDescriptor.symbolicTraits
        return (t.contains(.bold), t.contains(.italic))
    }

    /// Width of the writing column: 65 characters, as in Omawrite.
    var columnWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: regular]).width * 65
    }
}
