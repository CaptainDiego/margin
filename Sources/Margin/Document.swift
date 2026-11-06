import AppKit

@objc(Document)
final class Document: NSDocument {
    private var text = ""
    /// Written back in the encoding it was read in, so a Latin-1 or UTF-16
    /// file isn't silently re-encoded by an edit.
    private var encoding: String.Encoding = .utf8
    private(set) var editor: EditorViewController?
    private var autosaveTimer: Timer?

    // Native macOS saving: Versions, crash-safe drafts for untitled documents,
    // and the "file changed by another app" warning come for free.
    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let editor = EditorViewController(document: self)
        self.editor = editor

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.page
        window.minSize = NSSize(width: 480, height: 320)
        window.contentViewController = editor

        let controller = EditorWindowController(window: window)
        addWindowController(controller)
        if NSDocumentController.shared.documents.filter({ $0.windowControllers.count > 0 }).count <= 1 {
            window.center()
        }
        editor.load(text)
        window.makeFirstResponder(editor.textView)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let bom16 = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        let candidates: [String.Encoding] = bom16 ? [.utf16] : [.utf8, .isoLatin1]
        guard let (string, used) = candidates.lazy
                .compactMap({ e in String(data: data, encoding: e).map { ($0, e) } }).first else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = string
        encoding = used
        editor?.load(string)
    }

    override func data(ofType typeName: String) throws -> Data {
        if let editor { text = editor.string }
        guard let data = text.data(using: encoding) else {
            // e.g. an emoji typed into a Latin-1 file: refuse rather than mangle it.
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    // MARK: Saving

    /// Once a document has a file, edits are saved a moment after you stop
    /// typing. Untitled drafts wait for ⌘S, so Margin never picks a file name.
    func textDidChange() {
        // NSTextView keeps its typing undo group open, so the document wouldn't
        // learn it's edited until coalescing breaks. Mark it now.
        if !isDocumentEdited { updateChangeCount(.changeDone) }
        autosaveTimer?.invalidate()
        guard fileURL != nil else { editor?.refreshStatus(); return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self, self.fileURL != nil, self.isDocumentEdited else { return }
            self.editor?.textView.breakUndoCoalescing()
            self.autosave(withImplicitCancellability: false) { _ in self.editor?.refreshStatus() }
        }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        editor?.refreshStatus()
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            completionHandler(error)
            DispatchQueue.main.async { self?.editor?.refreshStatus() }
        }
    }

    override var fileURL: URL? {
        didSet { DispatchQueue.main.async { [weak self] in self?.editor?.refreshStatus() } }
    }

    // MARK: External changes (git checkout, another editor…)

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async { [weak self] in self?.reloadIfChangedOnDisk() }
    }

    private func reloadIfChangedOnDisk() {
        guard let url = fileURL, !isDocumentEdited,
              let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let known = fileModificationDate,
              modified.timeIntervalSince(known) > 0.01 else { return }
        try? revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo
        info.horizontalPagination = .fit
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.appearance = NSAppearance(named: .aqua)
        view.isRichText = false
        let fonts = Fonts(size: 11)
        view.textStorage?.setAttributedString(NSAttributedString(
            string: editor?.string ?? text,
            attributes: [.font: fonts.regular, .foregroundColor: NSColor.black, .paragraphStyle: fonts.paragraph]))
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    override init(window: NSWindow?) {
        super.init(window: window)
        window?.delegate = self
        shouldCascadeWindows = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }
}
