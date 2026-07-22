import AppKit

final class AppearancePreferences {
    static let shared = AppearancePreferences()

    private let backgroundColorKey = "TinyTasksBackgroundColor"
    private let textColorKey = "TinyTasksTextColor"
    private let lineColorKey = "TinyTasksLineColor"
    private let listTitleKey = "TinyTasksListTitle"

    private init() {}

    var backgroundColor: NSColor {
        get { storedColor(forKey: backgroundColorKey) ?? .windowBackgroundColor }
        set { storeColor(newValue, forKey: backgroundColorKey) }
    }

    var textColor: NSColor {
        get { storedColor(forKey: textColorKey) ?? .labelColor }
        set { storeColor(newValue, forKey: textColorKey) }
    }

    var lineColor: NSColor {
        get { storedColor(forKey: lineColorKey) ?? .separatorColor }
        set { storeColor(newValue, forKey: lineColorKey) }
    }

    var listTitle: String {
        get {
            let value = UserDefaults.standard.string(forKey: listTitleKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value! : "Tiny Tasks"
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(
                trimmed.isEmpty ? "Tiny Tasks" : trimmed,
                forKey: listTitleKey
            )
        }
    }

    func resetColors() {
        UserDefaults.standard.removeObject(forKey: backgroundColorKey)
        UserDefaults.standard.removeObject(forKey: textColorKey)
        UserDefaults.standard.removeObject(forKey: lineColorKey)
    }

    private func storedColor(forKey key: String) -> NSColor? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: data
            )
        else {
            return nil
        }
        return color
    }

    private func storeColor(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: color,
            requiringSecureCoding: true
        ) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}



private enum TaskTextAppearance {
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    static func apply(
        to text: NSMutableAttributedString,
        range: NSRange,
        textColor: NSColor
    ) {
        guard range.length > 0 else { return }

        text.beginEditing()
        text.removeAttribute(.font, range: range)
        text.removeAttribute(.foregroundColor, range: range)
        text.removeAttribute(.backgroundColor, range: range)
        text.addAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: range)

        text.enumerateAttribute(.link, in: range) { value, linkRange, _ in
            guard value != nil else { return }
            text.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: linkRange)
        }
        text.endEditing()
    }

    static func styled(
        _ source: NSAttributedString,
        textColor: NSColor,
        isCompleted: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let range = NSRange(location: 0, length: result.length)
        apply(to: result, range: range, textColor: textColor)

        if isCompleted, range.length > 0 {
            result.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
        }

        return result
    }
}

private enum TaskTextArchive {
    static func data(from text: NSAttributedString) -> Data? {
        let range = NSRange(location: 0, length: text.length)
        guard range.length > 0 else { return nil }

        return try? text.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func attributedString(from data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
}

private final class TaskTextFieldEditor: NSTextView {
    override func readSelection(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType
    ) -> Bool {
        let replacementRange = selectedRange()
        let previousLength = textStorage?.length ?? 0

        guard super.readSelection(from: pasteboard, type: type),
              let textStorage else {
            return false
        }

        let insertedLength = textStorage.length - (previousLength - replacementRange.length)
        let insertedRange = NSRange(
            location: replacementRange.location,
            length: max(0, insertedLength)
        )

        if insertedRange.length > 0,
           NSMaxRange(insertedRange) <= textStorage.length {
            TaskTextAppearance.apply(
                to: textStorage,
                range: insertedRange,
                textColor: AppearancePreferences.shared.textColor
            )
        }

        var attributes = typingAttributes
        attributes[.font] = TaskTextAppearance.font
        attributes[.foregroundColor] = AppearancePreferences.shared.textColor
        attributes.removeValue(forKey: .backgroundColor)
        typingAttributes = attributes
        didChangeText()

        return true
    }
}

final class TinyTasksWindow: NSWindow {
    private lazy var taskFieldEditor: TaskTextFieldEditor = {
        let editor = TaskTextFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        editor.isRichText = true
        return editor
    }()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if object is TaskTextField {
            return taskFieldEditor
        }

        return super.fieldEditor(createFlag, for: object)
    }
}

final class TaskButton: NSButton {
    weak var taskItem: TaskItem?
    var dragHandler: ((TaskButton, NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard dragHandler != nil else {
            super.mouseDown(with: event)
            return
        }

        let startingPoint = event.locationInWindow
        var shouldContinue = true

        while shouldContinue {
            guard let nextEvent = window?.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                break
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let point = nextEvent.locationInWindow
                let distance = hypot(
                    point.x - startingPoint.x,
                    point.y - startingPoint.y
                )

                if distance >= 4 {
                    dragHandler?(self, nextEvent)
                    shouldContinue = false
                }

            case .leftMouseUp:
                state = (state == .on) ? .off : .on

                if let action {
                    NSApp.sendAction(action, to: target, from: self)
                }

                shouldContinue = false

            default:
                break
            }
        }
    }
}

final class TaskSelectionButton: NSButton {
    weak var taskItem: TaskItem?
    var clickHandler: ((TaskSelectionButton, NSEvent) -> Void)?
    var dragHandler: ((TaskSelectionButton, NSEvent) -> Void)?
    var contextMenuHandler: ((TaskSelectionButton, NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let startingPoint = event.locationInWindow

        while true {
            guard let nextEvent = window?.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else {
                return
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let point = nextEvent.locationInWindow
                let distance = hypot(
                    point.x - startingPoint.x,
                    point.y - startingPoint.y
                )

                if distance >= 4 {
                    dragHandler?(self, nextEvent)
                    return
                }

            case .leftMouseUp:
                clickHandler?(self, event)
                return

            default:
                break
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        contextMenuHandler?(self, event)
    }
}

final class TaskTextField: NSTextField {
    weak var taskItem: TaskItem?
}

final class ListTitleField: NSTextField {
    var onDoubleClick: (() -> Void)?
    var onRenameRequest: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRenameRequest?()
    }
}

final class TaskOutlineView: NSOutlineView {
    var deleteSelectionHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117),
           window?.firstResponder is NSTextView == false {
            deleteSelectionHandler?()
            return
        }

        super.keyDown(with: event)
    }
}

final class HeaderView: NSView {
    var onDoubleClick: (() -> Void)?
    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialMouseLocation,
              let initialWindowOrigin else { return }

        let current = NSEvent.mouseLocation
        let deltaX = current.x - initialMouseLocation.x
        let deltaY = current.y - initialMouseLocation.y

        window.setFrameOrigin(
            NSPoint(
                x: initialWindowOrigin.x + deltaX,
                y: initialWindowOrigin.y + deltaY
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowOrigin = nil
    }
}

final class TaskWindowController: NSWindowController,
                                  NSOutlineViewDataSource,
                                  NSOutlineViewDelegate,
                                  NSTextFieldDelegate,
                                  NSDraggingSource {

    private let store = TaskStore()
    private let outlineView = TaskOutlineView()
    private let scrollView = NSScrollView()
    private let headerView = HeaderView()
    private let footerView = NSView()
    private let addButton = NSButton(title: "+", target: nil, action: nil)
    private let pinButton = NSButton(title: "Pin Window", target: nil, action: nil)
    private let backgroundButton = NSButton(title: "Background Color…", target: nil, action: nil)
    private let settingsButton = NSButton(title: "⚙︎", target: nil, action: nil)
    private let searchField = NSSearchField()
    private let titleField = ListTitleField()
    private let topMenuButton = NSButton()

    private enum ColorTarget {
        case background
        case text
        case lines
    }

    private var colorTarget: ColorTarget = .background
    private var pendingCompletionMoves: [UUID: DispatchWorkItem] = [:]
    private var selectedTaskIDs: Set<UUID> = []
    private var selectionAnchorID: UUID?

    private let dragType = NSPasteboard.PasteboardType("com.local.TinyTasks.task")
    private var isCollapsed = false
    private var expandedFrame: NSRect?
    private var expandedMinimumSize = NSSize(width: 240, height: 120)
    private var footerHeightConstraint: NSLayoutConstraint?

    init() {
        let window = TinyTasksWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppearancePreferences.shared.listTitle
        window.center()
        window.setFrameAutosaveName("TinyTasksMainWindow")
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(width: 240, height: 120)

        super.init(window: window)
        configureUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.onDoubleClick = { [weak self] in
            self?.toggleCollapsed()
        }

        titleField.stringValue = AppearancePreferences.shared.listTitle
        titleField.onDoubleClick = { [weak self] in
            self?.toggleCollapsed()
        }
        titleField.onRenameRequest = { [weak self] in
            self?.promptToRenameList()
        }
        titleField.font = .boldSystemFont(ofSize: 13)
        titleField.alignment = .left
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        topMenuButton.title = "⋮"
        topMenuButton.target = self
        topMenuButton.action = #selector(showSettingsMenu(_:))
        topMenuButton.isBordered = false
        topMenuButton.font = .systemFont(ofSize: 18)
        topMenuButton.toolTip = "Options"
        topMenuButton.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(titleField)
        headerView.addSubview(topMenuButton)

        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("TaskColumn")
        )
        column.title = "Task"
        column.resizingMask = .autoresizingMask

        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 34
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.gridStyleMask = [.solidHorizontalGridLineMask]
        outlineView.indentationPerLevel = 14
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.allowsMultipleSelection = true
        outlineView.deleteSelectionHandler = { [weak self] in
            self?.deleteSelectedTasks()
        }
        outlineView.focusRingType = .none
        outlineView.selectionHighlightStyle = .none
        outlineView.target = self
        outlineView.doubleAction = #selector(beginEditingSelectedRow)

        outlineView.registerForDraggedTypes([dragType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        footerView.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addRootTask)
        addButton.isBordered = false
        addButton.font = .systemFont(ofSize: 22, weight: .light)
        addButton.toolTip = "Add task"
        addButton.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search…"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.target = self
        settingsButton.action = #selector(showSettingsMenu(_:))
        settingsButton.isBordered = false
        settingsButton.font = .systemFont(ofSize: 17)
        settingsButton.toolTip = "Options"
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        footerView.addSubview(addButton)
        footerView.addSubview(searchField)
        footerView.addSubview(settingsButton)

        contentView.addSubview(headerView)
        contentView.addSubview(scrollView)
        contentView.addSubview(footerView)

        let footerHeightConstraint = footerView.heightAnchor.constraint(equalToConstant: 36)
        self.footerHeightConstraint = footerHeightConstraint

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),

            titleField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleField.leadingAnchor.constraint(
                equalTo: headerView.leadingAnchor,
                constant: 12
            ),
            titleField.trailingAnchor.constraint(
                equalTo: topMenuButton.leadingAnchor,
                constant: -6
            ),

            topMenuButton.trailingAnchor.constraint(
                equalTo: headerView.trailingAnchor,
                constant: -5
            ),
            topMenuButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            topMenuButton.widthAnchor.constraint(equalToConstant: 24),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerHeightConstraint,

            addButton.leadingAnchor.constraint(
                equalTo: footerView.leadingAnchor,
                constant: 4
            ),
            addButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),

            settingsButton.trailingAnchor.constraint(
                equalTo: footerView.trailingAnchor,
                constant: -5
            ),
            settingsButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),

            searchField.leadingAnchor.constraint(
                equalTo: addButton.trailingAnchor,
                constant: 5
            ),
            searchField.trailingAnchor.constraint(
                equalTo: settingsButton.leadingAnchor,
                constant: -5
            ),
            searchField.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: .tinyTasksStoreDidChange,
            object: store
        )

        applyAppearance()

        for task in store.tasks where task.isExpanded {
            outlineView.expandItem(task, expandChildren: true)
        }
    }

    private var searchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func taskMatchesSearch(_ task: TaskItem) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        if task.title.localizedCaseInsensitiveContains(searchQuery) { return true }
        return task.children.contains(where: taskMatchesSearch)
    }

    private func visibleRootTasks() -> [TaskItem] {
        store.tasks.filter(taskMatchesSearch)
    }

    private func visibleChildren(of task: TaskItem) -> [TaskItem] {
        task.children.filter(taskMatchesSearch)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        outlineView.reloadData()
        if !searchQuery.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
        }
    }

    @objc private func storeDidChange() {
        outlineView.reloadData()
        for task in store.tasks where task.isExpanded {
            outlineView.expandItem(task, expandChildren: true)
        }
    }

    @objc func undoAction(_ sender: Any?) {
        store.performUndo()
    }

    @objc func redoAction(_ sender: Any?) {
        store.performRedo()
    }


    private func promptToRenameList() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "Rename List"
        alert.informativeText = "Enter a new name for this list."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(string: titleField.stringValue)
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = input

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }

            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            self?.titleField.stringValue = trimmed
            AppearancePreferences.shared.listTitle = trimmed
        }

        DispatchQueue.main.async {
            input.selectText(nil)
        }
    }


    @objc private func showSettingsMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let background = NSMenuItem(
            title: "Background Color…",
            action: #selector(showBackgroundColorPickerFromMenu(_:)),
            keyEquivalent: ""
        )
        background.target = self
        menu.addItem(background)

        let textColor = NSMenuItem(
            title: "Text Color…",
            action: #selector(showTextColorPicker(_:)),
            keyEquivalent: ""
        )
        textColor.target = self
        menu.addItem(textColor)

        let lineColor = NSMenuItem(
            title: "Line Color…",
            action: #selector(showLineColorPicker(_:)),
            keyEquivalent: ""
        )
        lineColor.target = self
        menu.addItem(lineColor)

        let reset = NSMenuItem(
            title: "Reset Colors",
            action: #selector(resetColors(_:)),
            keyEquivalent: ""
        )
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        let pin = NSMenuItem(
            title: window?.level == .floating ? "Unpin Window" : "Pin Window on Top",
            action: #selector(togglePin),
            keyEquivalent: ""
        )
        pin.target = self
        menu.addItem(pin)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY),
            in: sender
        )
    }

    @objc private func showBackgroundColorPicker() {
        openColorPanel(
            target: .background,
            color: AppearancePreferences.shared.backgroundColor
        )
    }

    @objc func showBackgroundColorPickerFromMenu(_ sender: Any?) {
        showBackgroundColorPicker()
    }

    @objc private func showTextColorPicker(_ sender: Any?) {
        openColorPanel(
            target: .text,
            color: AppearancePreferences.shared.textColor
        )
    }

    @objc private func showLineColorPicker(_ sender: Any?) {
        openColorPanel(
            target: .lines,
            color: AppearancePreferences.shared.lineColor
        )
    }

    private func openColorPanel(target: ColorTarget, color: NSColor) {
        colorTarget = target

        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        let color = sender.color.usingColorSpace(.deviceRGB) ?? sender.color

        switch colorTarget {
        case .background:
            AppearancePreferences.shared.backgroundColor = color
        case .text:
            AppearancePreferences.shared.textColor = color
        case .lines:
            AppearancePreferences.shared.lineColor = color
        }

        applyAppearance()
    }

    private func applyAppearance() {
        let background = AppearancePreferences.shared.backgroundColor
        let textColor = AppearancePreferences.shared.textColor
        let lineColor = AppearancePreferences.shared.lineColor

        guard let contentView = window?.contentView else { return }

        contentView.layer?.backgroundColor = background.cgColor
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = background.cgColor
        headerView.layer?.borderWidth = 0.5
        headerView.layer?.borderColor = lineColor.cgColor

        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = background.cgColor
        footerView.layer?.borderWidth = 0.5
        footerView.layer?.borderColor = lineColor.cgColor

        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = background.cgColor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = background

        outlineView.backgroundColor = background
        outlineView.gridColor = lineColor

        titleField.textColor = textColor
        searchField.textColor = textColor
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search…",
            attributes: [.foregroundColor: textColor.withAlphaComponent(0.55)]
        )

        addButton.contentTintColor = textColor
        settingsButton.contentTintColor = textColor

        outlineView.reloadData()
    }

    @objc func resetColors(_ sender: Any?) {
        AppearancePreferences.shared.resetColors()
        applyAppearance()
    }

    @objc private func togglePin() {
        guard let window else { return }

        if window.level == .floating {
            window.level = .normal
            window.collectionBehavior = []
            pinButton.state = .off
            pinButton.toolTip = "Keep window on top"
        } else {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            pinButton.state = .on
            pinButton.toolTip = "Allow other windows above"
        }
    }

    private func toggleCollapsed() {
        guard let window else { return }

        let collapsedHeight: CGFloat = 34

        if isCollapsed {
            let collapsedFrame = window.frame

            window.minSize = expandedMinimumSize
            footerHeightConstraint?.constant = 36
            topMenuButton.isHidden = false
            scrollView.isHidden = false
            footerView.isHidden = false

            if var restored = expandedFrame {
                restored.origin.x = collapsedFrame.origin.x
                restored.origin.y = collapsedFrame.maxY - restored.height
                window.setFrame(restored, display: true, animate: true)
            }

            isCollapsed = false
        } else {
            expandedFrame = window.frame
            expandedMinimumSize = window.minSize

            window.makeFirstResponder(nil)
            topMenuButton.isHidden = true
            scrollView.isHidden = true
            footerView.isHidden = true
            footerHeightConstraint?.constant = 0
            window.contentView?.layoutSubtreeIfNeeded()
            window.minSize = NSSize(width: expandedMinimumSize.width, height: collapsedHeight)

            let currentTop = window.frame.maxY
            var frame = window.frame
            frame.size.height = collapsedHeight
            frame.origin.y = currentTop - collapsedHeight
            window.setFrame(frame, display: true, animate: true)

            isCollapsed = true
        }
    }

    @objc private func addRootTask() {
        let item = store.addRootTask()
        outlineView.reloadData()
        beginEditing(item)
    }

    @objc private func beginEditingSelectedRow() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0 else { return }
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    private func beginEditing(_ item: TaskItem) {
        let row = outlineView.row(forItem: item)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let task = item as? TaskItem {
            return visibleChildren(of: task).count
        }
        return visibleRootTasks().count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let task = item as? TaskItem {
            return visibleChildren(of: task)[index]
        }
        return visibleRootTasks()[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let task = item as? TaskItem else { return false }
        return !task.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        heightOfRowByItem item: Any
    ) -> CGFloat {
        guard let task = item as? TaskItem else { return 34 }

        let row = outlineView.row(forItem: task)
        let level = row >= 0 ? outlineView.level(forRow: row) : 0
        let availableWidth = max(
            80,
            outlineView.bounds.width
                - 62
                - CGFloat(level) * outlineView.indentationPerLevel
        )

        let size = styledTitle(for: task).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size

        return max(34, ceil(size.height) + 14)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let task = item as? TaskItem else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("TaskCell")
        let cell: NSTableCellView

        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self)
            as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let checkbox = TaskButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleCompleted(_:))
            )
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkbox.identifier = NSUserInterfaceItemIdentifier("CheckBox")

            let textField = TaskTextField()
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBordered = false
            textField.drawsBackground = false
            textField.focusRingType = .none
            textField.delegate = self
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.identifier = NSUserInterfaceItemIdentifier("TaskText")
            textField.allowsEditingTextAttributes = true
            textField.maximumNumberOfLines = 0
            textField.lineBreakMode = .byWordWrapping
            textField.cell?.wraps = true
            textField.cell?.isScrollable = false

            let divider = NSView()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.identifier = NSUserInterfaceItemIdentifier("RowDivider")
            divider.wantsLayer = true

            let selectionButton = TaskSelectionButton(title: "", target: nil, action: nil)
            selectionButton.isBordered = false
            selectionButton.imagePosition = .imageOnly
            selectionButton.imageScaling = .scaleProportionallyDown
            selectionButton.toolTip = "Select, drag, or right-click task"
            selectionButton.translatesAutoresizingMaskIntoConstraints = false
            selectionButton.identifier = NSUserInterfaceItemIdentifier("SelectionButton")

            cell.addSubview(checkbox)
            cell.addSubview(divider)
            cell.addSubview(textField)
            cell.addSubview(selectionButton)
            cell.textField = textField

            NSLayoutConstraint.activate([
                checkbox.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                checkbox.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
                checkbox.widthAnchor.constraint(equalToConstant: 18),

                divider.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 29),
                divider.topAnchor.constraint(equalTo: cell.topAnchor),
                divider.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                divider.widthAnchor.constraint(equalToConstant: 0.5),

                textField.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: selectionButton.leadingAnchor, constant: -4),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -7),

                selectionButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                selectionButton.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5),
                selectionButton.widthAnchor.constraint(equalToConstant: 26),
                selectionButton.heightAnchor.constraint(equalToConstant: 24)
            ])
        }

        guard let checkbox = cell.subviews.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("CheckBox")
        }) as? TaskButton,
        let textField = cell.textField as? TaskTextField,
        let selectionButton = cell.subviews.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("SelectionButton")
        }) as? TaskSelectionButton else {
            return cell
        }

        if let divider = cell.subviews.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("RowDivider")
        }) {
            divider.layer?.backgroundColor =
                AppearancePreferences.shared.lineColor.cgColor
        }

        checkbox.state = task.isCompleted ? .on : .off
        checkbox.taskItem = task
        checkbox.dragHandler = { [weak self] button, event in
            self?.beginCheckboxDrag(from: button, event: event)
        }
        selectionButton.taskItem = task
        selectionButton.clickHandler = { [weak self] button, event in
            self?.handleSelectionClick(button, event: event)
        }
        selectionButton.dragHandler = { [weak self] button, event in
            self?.beginSelectionDrag(from: button, event: event)
        }
        selectionButton.contextMenuHandler = { [weak self] button, event in
            self?.showSelectionMenu(for: button, event: event)
        }

        let isSelected = selectedTaskIDs.contains(task.id)
        selectionButton.image = NSImage(
            systemSymbolName: isSelected ? "largecircle.fill.circle" : "circle",
            accessibilityDescription: isSelected ? "Selected task" : "Unselected task"
        )
        selectionButton.contentTintColor = AppearancePreferences.shared.textColor
        selectionButton.toolTip = isSelected
            ? "Selected — drag or right-click"
            : "Select, drag, or right-click"

        textField.taskItem = task
        textField.attributedStringValue = styledTitle(for: task)

        return cell
    }

    private func styledTitle(for task: TaskItem) -> NSAttributedString {
        let selectedTextColor = AppearancePreferences.shared.textColor
        let baseColor: NSColor = task.isCompleted
            ? selectedTextColor.withAlphaComponent(0.48)
            : selectedTextColor

        let result = NSMutableAttributedString(
            attributedString: TaskTextAppearance.styled(
                storedTitle(for: task),
                textColor: baseColor,
                isCompleted: task.isCompleted
            )
        )

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: (task.title as NSString).length)
            for match in detector.matches(in: task.title, options: [], range: range) {
                guard let url = match.url else { continue }
                result.addAttributes([
                    .link: url,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: match.range)
            }
        }

        return result
    }

    private func editableTitle(for task: TaskItem) -> NSAttributedString {
        TaskTextAppearance.styled(
            storedTitle(for: task),
            textColor: AppearancePreferences.shared.textColor,
            isCompleted: false
        )
    }

    private func storedTitle(for task: TaskItem) -> NSAttributedString {
        if let data = task.richTextData,
           let attributedTitle = TaskTextArchive.attributedString(from: data),
           attributedTitle.string == task.title {
            return attributedTitle
        }

        return NSAttributedString(string: task.title)
    }

    @objc private func toggleCompleted(_ sender: TaskButton) {
        guard let clickedTask = sender.taskItem else { return }

        let selectedTasks = selectedTaskItems()
        let affectedTasks = selectedTasks.contains(where: { $0.id == clickedTask.id })
            ? selectedTasks
            : [clickedTask]
        let completed = sender.state == .on

        for task in affectedTasks {
            pendingCompletionMoves[task.id]?.cancel()
            pendingCompletionMoves[task.id] = nil
        }

        store.setCompleted(affectedTasks, completed: completed)
        outlineView.reloadData()

        guard completed else { return }

        for task in affectedTasks {
            let taskID = task.id
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }

                self.pendingCompletionMoves[taskID] = nil

                guard let currentTask = self.store.task(withID: taskID),
                      currentTask.isCompleted else {
                    return
                }

                self.store.moveTaskToAbsoluteBottom(currentTask, registerUndo: false)
                self.store.save()
                self.outlineView.reloadData()
            }

            pendingCompletionMoves[taskID] = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 1.0,
                execute: workItem
            )
        }
    }

    private func handleSelectionClick(
        _ sender: TaskSelectionButton,
        event: NSEvent
    ) {
        guard let task = sender.taskItem else { return }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.option) {
            selectedTaskIDs.removeAll()
            selectionAnchorID = nil
        } else if modifiers.contains(.shift),
                  let anchorID = selectionAnchorID,
                  let anchorRow = visibleRow(forTaskID: anchorID),
                  let clickedRow = visibleRow(forTaskID: task.id) {
            let range = min(anchorRow, clickedRow)...max(anchorRow, clickedRow)
            let rangeIDs = Set(range.compactMap { row -> UUID? in
                (outlineView.item(atRow: row) as? TaskItem)?.id
            })

            if modifiers.contains(.command) {
                selectedTaskIDs.formUnion(rangeIDs)
            } else {
                selectedTaskIDs = rangeIDs
            }
        } else {
            if selectedTaskIDs.contains(task.id) {
                selectedTaskIDs.remove(task.id)
            } else {
                selectedTaskIDs.insert(task.id)
            }
            selectionAnchorID = task.id
        }

        outlineView.reloadData()
    }

    private func visibleRow(forTaskID id: UUID) -> Int? {
        for row in 0..<outlineView.numberOfRows {
            if let task = outlineView.item(atRow: row) as? TaskItem,
               task.id == id {
                return row
            }
        }
        return nil
    }

    private func selectedTaskItems() -> [TaskItem] {
        (0..<outlineView.numberOfRows).compactMap { row in
            guard let task = outlineView.item(atRow: row) as? TaskItem,
                  selectedTaskIDs.contains(task.id) else {
                return nil
            }
            return task
        }
    }

    private func deleteSelectedTasks() {
        let tasks = selectedTaskItems()
        guard !tasks.isEmpty else { return }

        store.delete(tasks)
        selectedTaskIDs.subtract(tasks.map(\.id))
        if let anchorID = selectionAnchorID,
           tasks.contains(where: { $0.id == anchorID }) {
            selectionAnchorID = nil
        }
        outlineView.reloadData()
    }

    private func showSelectionMenu(
        for sender: TaskSelectionButton,
        event: NSEvent
    ) {
        guard let task = sender.taskItem else { return }

        if !selectedTaskIDs.contains(task.id) {
            selectedTaskIDs = [task.id]
            selectionAnchorID = task.id
            outlineView.reloadData()
        }

        let selectedTasks = selectedTaskItems()
        guard !selectedTasks.isEmpty else { return }

        let menu = NSMenu()

        if selectedTasks.count == 1,
           let onlyTask = selectedTasks.first,
           store.parent(of: onlyTask) == nil {
            let addSubtask = NSMenuItem(
                title: "Add Subtask",
                action: #selector(addSubtaskFromMenu(_:)),
                keyEquivalent: ""
            )
            addSubtask.target = self
            addSubtask.representedObject = onlyTask
            menu.addItem(addSubtask)
            menu.addItem(.separator())
        }

        let delete = NSMenuItem(
            title: selectedTasks.count == 1 ? "Delete" : "Delete Selected",
            action: #selector(deleteSelectionFromMenu(_:)),
            keyEquivalent: ""
        )
        delete.target = self
        menu.addItem(delete)

        NSMenu.popUpContextMenu(menu, with: event, for: sender)
    }

    @objc private func addSubtaskFromMenu(_ sender: NSMenuItem) {
        guard let parent = sender.representedObject as? TaskItem else { return }
        let child = store.addChild(to: parent)
        outlineView.reloadItem(parent, reloadChildren: true)
        outlineView.expandItem(parent)
        beginEditing(child)
    }

    @objc private func deleteSelectionFromMenu(_ sender: NSMenuItem) {
        deleteSelectedTasks()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              let field = control as? TaskTextField,
              let task = field.taskItem else {
            return false
        }

        let modifiers = NSApp.currentEvent?.modifierFlags
            .intersection(.deviceIndependentFlagsMask) ?? []

        if modifiers.contains(.command) {
            store.rename(task, to: textView.string)
            let newTask = store.addSibling(after: task)
            outlineView.reloadData()
            beginEditing(newTask)
            return true
        }

        if modifiers.contains(.shift) {
            store.rename(task, to: textView.string)

            if let parent = store.parent(of: task) {
                let sibling = store.addSibling(after: task)
                outlineView.reloadItem(parent, reloadChildren: true)
                outlineView.expandItem(parent)
                beginEditing(sibling)
            } else {
                let child = store.addChild(to: task)
                outlineView.reloadItem(task, reloadChildren: true)
                outlineView.expandItem(task)
                beginEditing(child)
            }

            return true
        }

        textView.insertNewlineIgnoringFieldEditor(nil)
        updateTaskText(field, from: textView)
        return true
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? TaskTextField,
              let editor = field.currentEditor() as? NSTextView else {
            return
        }

        updateTaskText(field, from: editor)
    }

    private func updateTaskText(_ field: TaskTextField, from editor: NSTextView) {
        guard let task = field.taskItem else { return }

        let attributedTitle = editor.textStorage.map {
            TaskTextAppearance.styled(
                NSAttributedString(attributedString: $0),
                textColor: AppearancePreferences.shared.textColor,
                isCompleted: false
            )
        } ?? NSAttributedString(string: editor.string)

        store.updateText(
            task,
            title: attributedTitle.string,
            richTextData: TaskTextArchive.data(from: attributedTitle)
        )
        outlineView.noteHeightOfRows(
            withIndexesChanged: IndexSet(integersIn: 0..<max(0, outlineView.numberOfRows))
        )
        expandWindowToFitContentIfNeeded()
    }

    private func expandWindowToFitContentIfNeeded() {
        guard !isCollapsed,
              let window,
              let screen = window.screen else {
            return
        }

        let contentHeight = outlineView.bounds.height + 74
        let maximumHeight = screen.visibleFrame.height
        let desiredHeight = min(maximumHeight, max(window.frame.height, contentHeight))

        guard desiredHeight > window.frame.height + 1 else { return }

        var frame = window.frame
        let top = frame.maxY
        frame.size.height = desiredHeight
        frame.origin.y = max(screen.visibleFrame.minY, top - desiredHeight)
        window.setFrame(frame, display: true, animate: false)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if let object = notification.object as AnyObject?,
           object === titleField {
            titleField.textColor = AppearancePreferences.shared.textColor
            return
        }

        guard let field = notification.object as? TaskTextField,
              let task = field.taskItem else { return }

        field.textColor = AppearancePreferences.shared.textColor

        if let editor = field.currentEditor() as? NSTextView,
           let textStorage = editor.textStorage {
            let selectedRange = editor.selectedRange()
            textStorage.setAttributedString(editableTitle(for: task))
            let selectionLocation = min(selectedRange.location, textStorage.length)
            editor.setSelectedRange(
                NSRange(
                    location: selectionLocation,
                    length: min(
                        selectedRange.length,
                        textStorage.length - selectionLocation
                    )
                )
            )

            var attributes = editor.typingAttributes
            attributes[.font] = TaskTextAppearance.font
            attributes[.foregroundColor] = AppearancePreferences.shared.textColor
            attributes.removeValue(forKey: .backgroundColor)
            editor.typingAttributes = attributes
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if let object = notification.object as AnyObject?,
           object === titleField {
            AppearancePreferences.shared.listTitle = titleField.stringValue
            titleField.stringValue = AppearancePreferences.shared.listTitle
            window?.title = AppearancePreferences.shared.listTitle
            return
        }

        guard let field = notification.object as? TaskTextField,
              let task = field.taskItem else {
            return
        }

        if let editor = field.currentEditor() as? NSTextView {
            updateTaskText(field, from: editor)
        } else {
            store.rename(task, to: field.stringValue)
        }
        outlineView.reloadItem(task)
        outlineView.noteHeightOfRows(
            withIndexesChanged: IndexSet(integersIn: 0..<max(0, outlineView.numberOfRows))
        )
        expandWindowToFitContentIfNeeded()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let task = notification.userInfo?["NSObject"] as? TaskItem else { return }
        store.setExpanded(task, true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let task = notification.userInfo?["NSObject"] as? TaskItem else { return }
        store.setExpanded(task, false)
    }

    private func beginSelectionDrag(
        from button: TaskSelectionButton,
        event: NSEvent
    ) {
        guard let clickedTask = button.taskItem else { return }

        if !selectedTaskIDs.contains(clickedTask.id) {
            selectedTaskIDs = [clickedTask.id]
            selectionAnchorID = clickedTask.id
            outlineView.reloadData()
        }

        let tasks = selectedTaskItems()
        guard !tasks.isEmpty else { return }

        let idString = tasks.map { $0.id.uuidString }.joined(separator: ",")
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(idString, forType: dragType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = NSImage(
            systemSymbolName: tasks.count > 1 ? "square.stack.3d.up.fill" : "circle.fill",
            accessibilityDescription: tasks.count > 1 ? "Selected tasks" : "Selected task"
        )

        draggingItem.setDraggingFrame(button.bounds, contents: image)
        button.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    private func draggedTasks(from info: NSDraggingInfo) -> [TaskItem] {
        guard let value = info.draggingPasteboard.string(forType: dragType) else {
            return []
        }

        return value
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
            .compactMap { store.task(withID: $0) }
    }

    private func beginCheckboxDrag(from button: TaskButton, event: NSEvent) {
        guard let task = button.taskItem else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(task.id.uuidString, forType: dragType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        let image = button.image ?? NSImage(
            systemSymbolName: task.isCompleted ? "checkmark.square.fill" : "square",
            accessibilityDescription: "Task"
        )

        draggingItem.setDraggingFrame(
            button.bounds,
            contents: image
        )

        button.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    // MARK: - Drag and drop

    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {
        guard let task = item as? TaskItem else { return nil }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(task.id.uuidString, forType: dragType)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let draggedTasks = draggedTasks(from: info)
        guard let draggedTask = draggedTasks.first else {
            return []
        }

        // NSOutlineView tends to propose only "between row" drops for leaf tasks.
        // When the pointer is over the middle of any task row, explicitly turn
        // that into a drop ON the task so it becomes a new subtask—even when
        // the destination task currently has no children.
        let localPoint = outlineView.convert(
            info.draggingLocation,
            from: nil
        )
        let hoveredRow = outlineView.row(at: localPoint)

        if hoveredRow >= 0,
           let hoveredTask = outlineView.item(atRow: hoveredRow) as? TaskItem,
           !draggedTasks.contains(where: { $0.id == hoveredTask.id }),
           store.parent(of: hoveredTask) == nil {
            let rowFrame = outlineView.rect(ofRow: hoveredRow)
            let centralDropZone = rowFrame.insetBy(
                dx: 0,
                dy: rowFrame.height * 0.22
            )

            if centralDropZone.contains(localPoint) {
                if draggedTasks.contains(where: {
                    store.contains(hoveredTask, inside: $0)
                }) {
                    return []
                }

                outlineView.setDropItem(
                    hoveredTask,
                    dropChildIndex: NSOutlineViewDropOnItemIndex
                )
                return .move
            }
        }

        if let proposedParent = item as? TaskItem {
            if store.parent(of: proposedParent) != nil {
                return []
            }

            if draggedTasks.contains(where: {
                store.contains(proposedParent, inside: $0)
            }) {
                return []
            }
        }

        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let draggedTasks = draggedTasks(from: info)
        guard !draggedTasks.isEmpty else {
            return false
        }

        let parent = item as? TaskItem

        if let parent, store.parent(of: parent) != nil {
            return false
        }

        let destinationIndex: Int

        if index == NSOutlineViewDropOnItemIndex {
            destinationIndex = parent?.children.count ?? store.tasks.count
        } else {
            destinationIndex = index
        }

        store.move(draggedTasks, toParent: parent, at: destinationIndex)
        selectedTaskIDs = Set(draggedTasks.map(\.id))
        outlineView.reloadData()

        if let parent {
            outlineView.expandItem(parent)
        }

        return true
    }
}
