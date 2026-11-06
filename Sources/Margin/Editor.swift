import AppKit

extension Notification.Name {
    static let fontSizeChanged = Notification.Name("MarginFontSizeChanged")
}

/// Plain-text editor: paste comes in as plain text, copy goes out as plain text,
/// no auto-bullets or substitutions. ⌘-click opens a link.
final class EditorTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let storage = textStorage {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            if index < storage.length,
               let link = storage.attribute(.mdLink, at: index, effectiveRange: nil) as? String,
               let url = URL(string: link),
               let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                // Only web and mail links: a document can't make Margin open
                // local files, apps or custom URL schemes.
                NSWorkspace.shared.open(url)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Right-click menu: Look Up / Translate, Cut, Copy, Paste. Nothing else
    /// (no Writing Tools, Font, Substitutions, Share or web search).
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        let keep: Set<String> = ["_rvMenuItemAction", "cut:", "copy:", "paste:"]
        for item in menu.items.reversed() where !item.isSeparatorItem {
            if !keep.contains(item.action.map(NSStringFromSelector) ?? "") { menu.removeItem(item) }
        }
        MenuCleaner.shared.clean(menu)
        return menu
    }

    /// Only plain text comes in, whether pasted or dropped.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
}

final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {
    weak var document: Document?

    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer()
    let glyphHider = GlyphHider()
    private(set) var textView: EditorTextView!
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let wordsLabel = NSTextField(labelWithString: "")
    private var highlighter: Highlighter!
    private var fonts = Fonts()

    private var pendingEdit: NSRange?
    private var lastSelection = NSRange(location: 0, length: 0)
    private var isLoading = false
    private var wordTimer: Timer?

    private static let footerHeight: CGFloat = 32
    private static let titlebarHeight: CGFloat = 28

    init(document: Document) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    var string: String { textView.string }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 780))

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = glyphHider
        layoutManager.allowsNonContiguousLayout = true
        storage.delegate = self
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        textContainer.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let tv = EditorTextView(frame: root.bounds, textContainer: textContainer)
        tv.delegate = self
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        if #available(macOS 15.0, *) { tv.writingToolsBehavior = .none }
        tv.drawsBackground = true
        tv.backgroundColor = Theme.page
        tv.insertionPointColor = Theme.text
        tv.selectedTextAttributes = [.backgroundColor: Theme.selection]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView = tv

        highlighter = Highlighter(storage: storage, fonts: fonts)
        tv.typingAttributes = highlighter.baseAttributes

        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.page
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        for label in [statusLabel, wordsLabel] {
            label.font = fonts.small
            label.textColor = Theme.muted
            label.alphaValue = 0.8
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(label)
        }
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.titlebarHeight),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.footerHeight),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            wordsLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            wordsLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: wordsLabel.leadingAnchor, constant: -16),
        ])

        view = root
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeChanged),
                                               name: .fontSizeChanged, object: nil)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateInsets()
    }

    private func updateInsets() {
        let width = scrollView.contentSize.width
        let column = min(fonts.columnWidth, max(360, width - fonts.columnWidth * 20 / 65))
        let side = max(24, ((width - column) / 2).rounded())
        let inset = NSSize(width: side, height: 22)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
    }

    // MARK: Loading

    func load(_ text: String) {
        isLoading = true
        let selection = textView.selectedRange()
        let visible = scrollView.contentView.bounds.origin
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.setAttributes(highlighter.baseAttributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        let length = storage.length
        let loc = min(selection.location, length)
        let restored = NSRange(location: loc, length: min(selection.length, length - loc))
        highlighter.selection = restored
        highlighter.restyleAll(progressive: true)
        textView.setSelectedRange(restored)
        lastSelection = restored
        scrollView.contentView.scroll(to: visible)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pendingEdit = nil
        isLoading = false
        updateWordCount()
        refreshStatus()
    }

    // MARK: Delegates

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isLoading else { return }
        pendingEdit = pendingEdit.map { NSUnionRange($0, editedRange) } ?? editedRange
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }
        let edited = pendingEdit ?? textView.selectedRange()
        pendingEdit = nil
        highlighter.selection = textView.selectedRange()
        highlighter.restyle(edited: edited)
        textView.typingAttributes = highlighter.baseAttributes
        scheduleWordCount()
        document?.textDidChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading, !textView.hasMarkedText() else { return }
        let new = textView.selectedRange()
        highlighter.selectionChanged(from: lastSelection, to: new)
        lastSelection = new
        textView.typingAttributes = highlighter.baseAttributes
    }

    // MARK: Footer

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    func refreshStatus() {
        guard let document, isViewLoaded else { return }
        var parts: [String] = []
        if let url = document.fileURL {
            parts.append(url.lastPathComponent)
            if document.isDocumentEdited {
                parts.append("Edited")
            } else {
                parts.append("Saved")
                if let date = document.fileModificationDate {
                    parts.append(Self.dateFormatter.string(from: date))
                }
            }
        } else {
            parts.append("Untitled")
            if !string.isEmpty { parts.append("Not saved") }
        }
        statusLabel.stringValue = parts.joined(separator: " · ")
    }

    private func scheduleWordCount() {
        wordTimer?.invalidate()
        wordTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.updateWordCount()
        }
    }

    private func updateWordCount() {
        var count = 0
        var inWord = false
        for scalar in string.unicodeScalars {
            let space = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !space && !inWord { count += 1 }
            inWord = !space
        }
        wordsLabel.stringValue = count == 1 ? "1 Word" : "\(count) Words"
    }

    // MARK: Font size

    @objc private func fontSizeChanged() {
        fonts = Fonts()
        highlighter.fonts = fonts
        storage.beginEditing()
        storage.setAttributes(highlighter.baseAttributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        highlighter.restyleAll()
        textView.typingAttributes = highlighter.baseAttributes
        updateInsets()
    }

    @objc func makeTextBigger(_ sender: Any?) { setFontSize(Fonts.size + 1) }
    @objc func makeTextSmaller(_ sender: Any?) { setFontSize(Fonts.size - 1) }
    @objc func makeTextActualSize(_ sender: Any?) { setFontSize(Fonts.defaultSize) }

    private func setFontSize(_ size: CGFloat) {
        Fonts.size = size
        NotificationCenter.default.post(name: .fontSizeChanged, object: nil)
    }

    // MARK: Markdown shortcuts

    @objc func toggleMarkdownBold(_ sender: Any?) { wrap("**") }
    @objc func toggleMarkdownItalic(_ sender: Any?) { wrap("_") }
    @objc func toggleMarkdownStrikethrough(_ sender: Any?) { wrap("~~") }

    @objc func insertMarkdownLink(_ sender: Any?) {
        let r = textView.selectedRange()
        let selected = (string as NSString).substring(with: r)
        let looksLikeURL = selected.hasPrefix("http://") || selected.hasPrefix("https://")
        if looksLikeURL {
            replace(r, with: "[](\(selected))", select: NSRange(location: r.location + 1, length: 0))
        } else {
            let caret = r.location + 1 + (selected as NSString).length + 2
            replace(r, with: "[\(selected)]()", select: NSRange(location: selected.isEmpty ? r.location + 1 : caret, length: 0))
        }
    }

    private func wrap(_ marker: String) {
        let ns = string as NSString
        let r = textView.selectedRange()
        let m = (marker as NSString).length
        let selected = ns.substring(with: r)

        if r.location >= m, NSMaxRange(r) + m <= ns.length,
           ns.substring(with: NSRange(location: r.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(r), length: m)) == marker {
            replace(NSRange(location: r.location - m, length: r.length + 2 * m), with: selected,
                    select: NSRange(location: r.location - m, length: r.length))
        } else if r.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: r.length - 2 * m))
            replace(r, with: inner, select: NSRange(location: r.location, length: r.length - 2 * m))
        } else {
            replace(r, with: marker + selected + marker, select: NSRange(location: r.location + m, length: r.length))
        }
    }

    private func replace(_ range: NSRange, with text: String, select: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        textView.setSelectedRange(select)
    }
}
