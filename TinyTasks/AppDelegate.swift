import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: TaskWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let controller = TaskWindowController()
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit TinyTasks",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(TaskWindowController.undoAction(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(TaskWindowController.redoAction(_:)),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let backgroundItem = NSMenuItem(
            title: "Background Color…",
            action: #selector(TaskWindowController.showBackgroundColorPickerFromMenu(_:)),
            keyEquivalent: ""
        )
        backgroundItem.target = nil
        viewMenu.addItem(backgroundItem)

        let resetBackgroundItem = NSMenuItem(
            title: "Reset Colors",
            action: #selector(TaskWindowController.resetColors(_:)),
            keyEquivalent: ""
        )
        resetBackgroundItem.target = nil
        viewMenu.addItem(resetBackgroundItem)

        NSApp.mainMenu = mainMenu
    }
}
