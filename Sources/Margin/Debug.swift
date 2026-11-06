#if DEBUG
import AppKit

// Test hooks for debug builds only (release builds don't contain this file's code).
//   MARGIN_SNAPSHOT=<png>   render the editor to a PNG (+ MARGIN_LIGHT, MARGIN_CARET=<n>, MARGIN_TYPE=<text>)
//   MARGIN_TOGGLE_APPEARANCE  cycle Light/Dark/System through the responder chain
//   MARGIN_DUMP_MENUS       print the menus, the Edit menu after opening, and the right-click menu

extension Timer { func fire2() { RunLoop.main.add(self, forMode: .eventTracking) } }

extension AppDelegate {
    func runDebugHooks() {
        if let path = ProcessInfo.processInfo.environment["MARGIN_SNAPSHOT"] { snapshot(to: path) }
        if ProcessInfo.processInfo.environment["MARGIN_TOGGLE_APPEARANCE"] != nil {
            // Shares the real app's settings, so put the user's choice back afterwards.
            let original = UserDefaults.standard.integer(forKey: "appearance")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                let item = NSMenuItem(); item.tag = original
                NSApp.sendAction(#selector(AppDelegate.chooseAppearance(_:)), to: nil, from: item)
            }
            for (i, tag) in [1, 2, 0, 1].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 0.7) {
                    let item = NSMenuItem(); item.tag = tag
                    print("switching to \(tag)"); fflush(stdout)
                    NSApp.sendAction(#selector(AppDelegate.chooseAppearance(_:)), to: nil, from: item)
                }
            }
    }
    if ProcessInfo.processInfo.environment["MARGIN_DUMP_MENUS"] != nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            func dump(_ menu: NSMenu, _ indent: String) {
                menu.update()
                for item in menu.items {
                    let mods = item.keyEquivalentModifierMask
                    let key = item.keyEquivalent.isEmpty ? "" : (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "")
                        + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + (mods.contains(.function) ? "fn" : "") + item.keyEquivalent
                    print(indent + (item.isSeparatorItem ? "----" : item.title), key, item.action.map { NSStringFromSelector($0) } ?? "")
                    if let sub = item.submenu, indent.count < 4 { dump(sub, indent + "  ") }
                }
            }
            NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: nil) { note in
                let menu = note.object as! NSMenu
                let i = note.userInfo?["NSMenuItemIndex"] as? Int ?? -1
                print("ADDED to \(menu.title): \(i < menu.items.count && i >= 0 ? menu.items[i].title : "?")")
            }
            print("== at launch"); dump(NSApp.mainMenu!, "")
            let edit = NSApp.mainMenu!.item(withTitle: "Edit")!.submenu!
            Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { _ in edit.cancelTracking() }.fire2()
            edit.popUp(positioning: nil, at: .zero, in: NSApp.orderedWindows.first?.contentView)
            print("== after opening Edit"); dump(edit, "  ")
            if let tv = NSApp.windows.compactMap({ ($0.contentViewController as? EditorViewController)?.textView }).first {
                tv.selectAll(nil)
                let point = tv.convert(NSPoint(x: tv.textContainerInset.width + 10, y: tv.textContainerInset.height + 10), to: nil)
                let ev = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: tv.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                print("== context menu", tv.menu(for: ev) == nil ? "nil" : "")
                if let m = tv.menu(for: ev) { dump(m, "  ") }
            }
            fflush(stdout)
        }
    }    }

    /// Debug aid: renders the front window to a PNG (no Screen Recording permission needed).
    func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let window = NSApp.orderedWindows.first,
                  let view = (window.contentViewController as? EditorViewController)?.textView else { return }
            if ProcessInfo.processInfo.environment["MARGIN_LIGHT"] != nil {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            if let caret = ProcessInfo.processInfo.environment["MARGIN_CARET"], let loc = Int(caret),
               let editor = (window.contentViewController as? EditorViewController) {
                editor.textView.setSelectedRange(NSRange(location: loc, length: 0))
            }
            if let typed = ProcessInfo.processInfo.environment["MARGIN_TYPE"],
               let editor = (window.contentViewController as? EditorViewController) {
                editor.textView.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                for ch in typed { editor.textView.insertText(String(ch), replacementRange: editor.textView.selectedRange()) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                view.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.visibleRect) else { return }
                view.cacheDisplay(in: view.visibleRect, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
#endif
