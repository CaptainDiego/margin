import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        applyAppearance()
    }

    // MARK: Appearance: 0 follows the system, 1 light, 2 dark.

    private var appearanceChoice: Int {
        get { UserDefaults.standard.integer(forKey: "appearance") }
        set { UserDefaults.standard.set(newValue, forKey: "appearance") }
    }

    private func applyAppearance() {
        NSApp.appearance = [nil, NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)][min(2, max(0, appearanceChoice))]
    }

    // Not "setAppearance:": that's NSView/NSWindow's own setter, and the menu
    // action would reach the text view first through the responder chain.
    @objc func chooseAppearance(_ sender: NSMenuItem) {
        appearanceChoice = sender.tag
        applyAppearance()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(chooseAppearance(_:)) { item.state = item.tag == appearanceChoice ? .on : .off }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuCleaner.shared.cleanAll()
        DispatchQueue.main.async { MenuCleaner.shared.cleanAll() }
        if CommandLine.arguments.contains("--make-default") { makeDefault(nil) }
        #if DEBUG
        runDebugHooks()
        #endif
    }

    /// Registers Margin as the default app for Markdown files.
    @objc func makeDefault(_ sender: Any?) {
        var types: [UTType] = []
        for id in ["net.daringfireball.markdown"] { if let t = UTType(id) { types.append(t) } }
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"] {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        let app = Bundle.main.bundleURL
        let group = DispatchGroup()
        var failures: [String] = []
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
                // Called on a background queue; collect results on main.
                DispatchQueue.main.async {
                    if let error { failures.append("\(type.identifier): \(error.localizedDescription)") }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            guard sender != nil || !failures.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = failures.isEmpty ? "Margin now opens your Markdown files." : "Couldn't set Margin as default"
            alert.informativeText = failures.joined(separator: "\n")
            alert.runModal()
        }
    }
}

/// macOS injects Writing Tools, AutoFill, Dictation, Emoji & Symbols and its own
/// fn-F full screen item into every app's menus. Margin keeps its menus to what
/// it does, so those are removed whenever a menu is about to show.
final class MenuCleaner: NSObject, NSMenuDelegate {
    static let shared = MenuCleaner()
    private static let blocked: Set<String> = ["showWritingTools:", "startDictation:", "orderFrontCharacterPalette:"]

    func menuNeedsUpdate(_ menu: NSMenu) { clean(menu) }

    func cleanAll() {
        for item in NSApp.mainMenu?.items ?? [] {
            guard let menu = item.submenu else { continue }
            menu.delegate = self
            clean(menu)
        }
    }

    func clean(_ menu: NSMenu) {
        for item in menu.items.reversed() where shouldRemove(item) { menu.removeItem(item) }
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem, previousWasSeparator { menu.removeItem(item) }
            else { previousWasSeparator = item.isSeparatorItem; item.isAlternate = false }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }

    private func shouldRemove(_ item: NSMenuItem) -> Bool {
        let action = item.action.map(NSStringFromSelector) ?? ""
        let children = item.submenu?.items.compactMap { $0.action.map(NSStringFromSelector) } ?? []
        if Self.blocked.contains(action) { return true }
        if children.contains("showWritingTools:") || children.contains(where: { $0.hasPrefix("_handleInsertFrom") }) { return true }
        if action == "toggleFullScreen:" {
            let mods = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            return !(item.keyEquivalent == "f" && mods == [.command, .control])
        }
        return false
    }
}

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Margin")
        app.addItem(withTitle: "About Margin", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Make Margin the Default for Markdown", action: #selector(AppDelegate.makeDefault(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let services = NSMenu()
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Margin", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Margin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(main, "File")
        file.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        recent.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu")
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        item(file, "Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift, .option])
        file.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Move To…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Revert To Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "Print…", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")

        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        findItem(find, "Find…", .showFindInterface, "f")
        findItem(find, "Find and Replace…", .showReplaceInterface, "f", [.command, .option])
        findItem(find, "Find Next", .nextMatch, "g")
        findItem(find, "Find Previous", .previousMatch, "g", [.command, .shift])
        findItem(find, "Use Selection for Find", .setSearchString, "e")

        let format = submenu(main, "Format")
        format.addItem(withTitle: "Bold", action: #selector(EditorViewController.toggleMarkdownBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(EditorViewController.toggleMarkdownItalic(_:)), keyEquivalent: "i")
        item(format, "Strikethrough", #selector(EditorViewController.toggleMarkdownStrikethrough(_:)), "x", [.command, .shift])
        format.addItem(withTitle: "Link", action: #selector(EditorViewController.insertMarkdownLink(_:)), keyEquivalent: "k")

        let view = submenu(main, "View")
        view.addItem(withTitle: "Bigger", action: #selector(EditorViewController.makeTextBigger(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "Smaller", action: #selector(EditorViewController.makeTextSmaller(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Actual Size", action: #selector(EditorViewController.makeTextActualSize(_:)), keyEquivalent: "0")
        view.addItem(.separator())
        let appearance = NSMenu(title: "Appearance")
        view.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "").submenu = appearance
        for (tag, title) in ["System", "Light", "Dark"].enumerated() {
            appearance.addItem(withTitle: title, action: #selector(AppDelegate.chooseAppearance(_:)), keyEquivalent: "").tag = tag
        }
        view.addItem(.separator())
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        return main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    @discardableResult
    private static func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                             _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        return item
    }

    private static func findItem(_ menu: NSMenu, _ title: String, _ action: NSTextFinder.Action,
                                 _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
        let item = item(menu, title, #selector(NSTextView.performFindPanelAction(_:)), key, mods)
        item.tag = action.rawValue
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
