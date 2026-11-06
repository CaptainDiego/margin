import AppKit

extension NSAttributedString.Key {
    /// Markdown markers drawn with no glyphs (see GlyphHider).
    static let mdHidden = NSAttributedString.Key("MarginHidden")
    /// Fence state at the start of the paragraph: 0 = prose, >0 = inside a code fence.
    static let mdState = NSAttributedString.Key("MarginState")
    /// Destination of a link, opened with ⌘-click.
    static let mdLink = NSAttributedString.Key("MarginLink")
}

/// Live Markdown styling in the spirit of Omawrite: the text on disk is exactly
/// what you typed; markers recede, and inline markers (**, _, ~~, [](…)) are
/// hidden unless the caret is in or against them.
final class Highlighter {
    private let storage: NSTextStorage
    var fonts: Fonts
    var selection = NSRange(location: 0, length: 0)

    init(storage: NSTextStorage, fonts: Fonts) {
        self.storage = storage
        self.fonts = fonts
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: fonts.regular, .foregroundColor: Theme.text, .paragraphStyle: fonts.paragraph]
    }

    // MARK: Entry points

    func restyleAll() {
        run(from: 0, through: storage.length)
    }

    /// Restyle the paragraphs an edit touched, then keep going while the fence
    /// state that flows into the next paragraph differs from what it had.
    func restyle(edited range: NSRange) {
        let s = storage.string as NSString
        let loc = min(range.location, s.length)
        let end = min(NSMaxRange(range), s.length)
        let para = s.paragraphRange(for: NSRange(location: loc, length: end - loc))
        run(from: para.location, through: NSMaxRange(para))
    }

    /// The caret moved: only the paragraphs it left and entered can show
    /// different markers.
    func selectionChanged(from old: NSRange, to new: NSRange) {
        selection = new
        let s = storage.string as NSString
        guard s.length > 0 else { return }
        var paragraphs: [NSRange] = []
        for r in [old, new] {
            let loc = min(r.location, s.length)
            let len = min(r.length, s.length - loc)
            let p = s.paragraphRange(for: NSRange(location: loc, length: len))
            if p.length > 0, !paragraphs.contains(where: { NSIntersectionRange($0, p).length > 0 }) {
                paragraphs.append(p)
            }
        }
        guard !paragraphs.isEmpty else { return }
        storage.beginEditing()
        for p in paragraphs {
            var loc = p.location
            while loc < NSMaxRange(p) {
                let line = s.paragraphRange(for: NSRange(location: loc, length: 0))
                let state = storage.attribute(.mdState, at: line.location, effectiveRange: nil) as? Int ?? 0
                _ = style(line: line, in: s, state: state)
                loc = NSMaxRange(line)
            }
        }
        storage.endEditing()
    }

    // MARK: Paragraph walk

    private func run(from start: Int, through mustReach: Int) {
        let s = storage.string as NSString
        guard s.length > 0 else { return }
        var state = stateEntering(start, in: s)
        var loc = start
        storage.beginEditing()
        while loc < s.length {
            if loc >= mustReach,
               storage.attribute(.mdState, at: loc, effectiveRange: nil) as? Int == state {
                break
            }
            let line = s.paragraphRange(for: NSRange(location: loc, length: 0))
            state = style(line: line, in: s, state: state)
            loc = NSMaxRange(line)
        }
        storage.endEditing()
    }

    /// The previous paragraph wasn't edited, so its stored state is good.
    private func stateEntering(_ location: Int, in s: NSString) -> Int {
        guard location > 0 else { return 0 }
        let prev = s.paragraphRange(for: NSRange(location: location - 1, length: 0))
        let prevState = storage.attribute(.mdState, at: prev.location, effectiveRange: nil) as? Int ?? 0
        return Self.nextState(prevState, s.substring(with: contentRange(prev, s)))
    }

    private func contentRange(_ line: NSRange, _ s: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location {
            let c = s.character(at: end - 1)
            if c == 10 || c == 13 || c == 0x2028 || c == 0x2029 { end -= 1 } else { break }
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    // MARK: Fences

    private static let openingFence = try! NSRegularExpression(pattern: "^ {0,3}(?:(`{3,})[^`]*|(~{3,}).*)$")
    private static let closingFence = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})\\s*$")

    static func nextState(_ state: Int, _ text: String) -> Int {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        if state > 0 {
            let fence = state - 1
            let length = fence / 2 + 3
            let marker: Character = fence % 2 == 1 ? "~" : "`"
            if let m = closingFence.firstMatch(in: text, range: all) {
                let run = ns.substring(with: m.range(at: 1))
                if run.count >= length, run.first == marker { return 0 }
            }
            return state
        }
        if let m = openingFence.firstMatch(in: text, range: all) {
            let backticks = m.range(at: 1).location != NSNotFound
            let length = backticks ? m.range(at: 1).length : m.range(at: 2).length
            return 1 + (length - 3) * 2 + (backticks ? 0 : 1)
        }
        return 0
    }

    // MARK: Styling one paragraph

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6}\\s+)(.*)$")
    private static let quote = try! NSRegularExpression(pattern: "^(\\s*>+\\s?)(.*)$")
    private static let list = try! NSRegularExpression(pattern: "^(\\s*(?:[-+*]|\\d+[.)])\\s+(?:\\[[ xX]\\]\\s+)?)")
    private static let rule = try! NSRegularExpression(pattern: "^ {0,3}([-*_])(?:\\s*\\1){2,}\\s*$")
    private static let codeSpan = try! NSRegularExpression(pattern: "(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)")

    private struct Markup {
        var content: NSRange
        var markers: [NSRange]
        var bold = false
        var italic = false
        var strike = false
        var link: String?
    }

    private static let inlinePatterns: [(NSRegularExpression, (inout Markup) -> Void)] = [
        (try! NSRegularExpression(pattern: "(?<![\\\\*])(\\*\\*)(?=\\S)(.+?)(?<=[^\\s\\\\])(\\*\\*)"), { $0.bold = true }),
        (try! NSRegularExpression(pattern: "(?<![\\\\\\w_])(__)(?=\\S)(.+?)(?<=[^\\s\\\\])(__)(?![\\w_])"), { $0.bold = true }),
        (try! NSRegularExpression(pattern: "(?<![\\\\*\\w])(\\*)(?![\\s*])(.+?)(?<![\\s*\\\\])(\\*)(?!\\*)"), { $0.italic = true }),
        (try! NSRegularExpression(pattern: "(?<![\\\\\\w_])(_)(?![\\s_])(.+?)(?<![\\s_\\\\])(_)(?![\\w_])"), { $0.italic = true }),
        (try! NSRegularExpression(pattern: "(?<!\\\\)(~~)(?=\\S)(.+?)(?<=\\S)(~~)"), { $0.strike = true }),
    ]
    private static let linkPattern = try! NSRegularExpression(
        pattern: "(?<!\\\\)(\\[)([^\\]\\n]+)(\\]\\(([^)\\s]*)(?:\\s+\"[^\"]*\")?\\))")

    /// Styles one paragraph given the fence state entering it; returns the state leaving it.
    private func style(line: NSRange, in s: NSString, state: Int) -> Int {
        var attrs = baseAttributes
        attrs[.mdState] = state
        storage.setAttributes(attrs, range: line)

        let content = contentRange(line, s)
        let text = s.substring(with: content)
        let next = Self.nextState(state, text)

        if state > 0 || next > 0 {
            // Fence lines recede like a heading's #; the code between stays plain.
            let closing = state > 0 && next == 0
            let opening = state == 0
            if closing || opening {
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: content)
            }
            return next
        }
        guard content.length > 0 else { return 0 }

        let base = content.location
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func abs(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        if Self.rule.firstMatch(in: text, range: all) != nil {
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: content)
            return 0
        }
        if let m = Self.heading.firstMatch(in: text, range: all) {
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: abs(m.range(at: 1)))
            storage.addAttribute(.font, value: fonts.bold, range: abs(m.range(at: 2)))
        } else if let m = Self.quote.firstMatch(in: text, range: all) {
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: abs(m.range(at: 1)))
            storage.addAttributes([.foregroundColor: Theme.muted, .font: fonts.italic], range: abs(m.range(at: 2)))
        } else if let m = Self.list.firstMatch(in: text, range: all) {
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: abs(m.range(at: 1)))
        }

        guard text.contains(where: { "`*_~[".contains($0) }) else { return 0 }

        // Code spans first: nothing inside them is markup.
        let codes = Self.codeSpan.matches(in: text, range: all).map { $0.range }
        for r in codes {
            let ticks = (ns.substring(with: r) as NSString).range(of: "^`+", options: .regularExpression).length
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: abs(NSRange(location: r.location, length: ticks)))
            storage.addAttribute(.foregroundColor, value: Theme.marker,
                                 range: abs(NSRange(location: NSMaxRange(r) - ticks, length: ticks)))
        }
        func inCode(_ r: NSRange) -> Bool { codes.contains { NSIntersectionRange($0, r).length > 0 } }

        var items: [Markup] = []
        for m in Self.linkPattern.matches(in: text, range: all) where !inCode(m.range(at: 1)) && !inCode(m.range(at: 3)) {
            items.append(Markup(content: m.range(at: 2), markers: [m.range(at: 1), m.range(at: 3)],
                                link: ns.substring(with: m.range(at: 4))))
        }
        for (regex, apply) in Self.inlinePatterns {
            for m in regex.matches(in: text, range: all) {
                let open = m.range(at: 1), close = m.range(at: 3)
                guard !inCode(open), !inCode(close) else { continue }
                // A marker already claimed by another span (e.g. a link destination) isn't markup.
                guard !items.contains(where: { $0.markers.contains { NSIntersectionRange($0, open).length > 0 || NSIntersectionRange($0, close).length > 0 } }) else { continue }
                var item = Markup(content: m.range(at: 2), markers: [open, close])
                apply(&item)
                items.append(item)
            }
        }

        for item in items {
            let r = abs(item.content)
            if item.bold || item.italic { addTraits(r, bold: item.bold, italic: item.italic) }
            if item.strike { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            if let url = item.link {
                storage.addAttributes([.foregroundColor: Theme.link,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .mdLink: url], range: r)
            }
        }

        // Last, so no enclosing style shows a marker that should be hidden.
        let sel = selection
        for item in items {
            let start = abs(item.markers[0]).location
            let end = NSMaxRange(abs(item.markers[1]))
            let atCaret = sel.location <= end && NSMaxRange(sel) >= start
            for marker in item.markers {
                let r = abs(marker)
                if atCaret {
                    storage.addAttribute(.foregroundColor, value: Theme.marker, range: r)
                    storage.removeAttribute(.underlineStyle, range: r)
                } else {
                    storage.addAttribute(.mdHidden, value: true, range: r)
                }
            }
        }
        return 0
    }

    private func addTraits(_ range: NSRange, bold: Bool, italic: Bool) {
        storage.enumerateAttribute(.font, in: range) { value, r, _ in
            let current = (value as? NSFont).map(fonts.traits(of:)) ?? (bold: false, italic: false)
            storage.addAttribute(.font, value: fonts.font(bold: current.bold || bold,
                                                          italic: current.italic || italic), range: r)
        }
    }
}

/// Draws characters marked .mdHidden as nothing (TextKit 1 null glyphs),
/// so hidden markers take no space and the file's text is untouched.
final class GlyphHider: NSObject, NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var modified: [NSLayoutManager.GlyphProperty]?
        for i in 0..<count {
            let index = charIndexes[i]
            guard index < storage.length,
                  storage.attribute(.mdHidden, at: index, effectiveRange: nil) != nil else { continue }
            if modified == nil { modified = Array(UnsafeBufferPointer(start: props, count: count)) }
            modified![i] = .null
        }
        guard let modified else { return 0 }
        modified.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
        }
        return count
    }
}
