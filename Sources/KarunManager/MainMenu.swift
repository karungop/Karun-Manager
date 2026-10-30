import AppKit

/// The app's menu bar. Even though Karun Manager mostly lives in the status bar, macOS routes the standard
/// editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) and ⌘W/⌘Q/⌘, through these menus — without them, text fields in
/// the window and the HUDs can't copy or paste.
@MainActor
enum MainMenu {
    struct Actions {
        let openSettings: () -> Void
        let newTask: () -> Void
        let find: () -> Void
    }

    static func install(_ actions: Actions) {
        let handler = MenuActionHandler(actions: actions)
        let menu = NSMenu()
        menu.addItem(submenu(appMenu(handler)))
        menu.addItem(submenu(fileMenu(handler)))
        menu.addItem(submenu(editMenu(handler)))
        menu.addItem(submenu(windowMenu()))
        NSApp.mainMenu = menu
        MenuActionHandler.retained = handler
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func appMenu(_ handler: MenuActionHandler) -> NSMenu {
        let menu = NSMenu(title: "Karun Manager")
        menu.addItem(withTitle: "About Karun Manager", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(MenuActionHandler.openSettings), ",", target: handler))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Karun Manager", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Karun Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ handler: MenuActionHandler) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Task", #selector(MenuActionHandler.newTask), "n", target: handler))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }

    private static func editMenu(_ handler: MenuActionHandler) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlain = menu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(item("Find", #selector(MenuActionHandler.find), "f", target: handler))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}

@MainActor
private final class MenuActionHandler: NSObject {
    /// NSMenuItem.target is weak; keep the handler alive for the app's lifetime.
    static var retained: MenuActionHandler?
    let actions: MainMenu.Actions

    init(actions: MainMenu.Actions) {
        self.actions = actions
    }

    @objc func openSettings() { actions.openSettings() }
    @objc func newTask() { actions.newTask() }
    @objc func find() { actions.find() }
}
