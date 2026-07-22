import Foundation
import AppKit

final class TaskStore {
    private(set) var tasks: [TaskItem] = []

    let undoManager = UndoManager()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()
    private var isRestoringSnapshot = false

    private var appSupportDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TinyTasks", isDirectory: true)
    }

    private var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("tasks.json")
    }

    private var backupsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    init() {
        load()
        moveCompletedToBottom(registerUndo: false)
    }

    func addRootTask() -> TaskItem {
        registerSnapshotUndo(actionName: "Add Task")
        let item = TaskItem(title: "New Task")
        tasks.insert(item, at: 0)
        save()
        return item
    }

    func addSibling(after task: TaskItem) -> TaskItem {
        registerSnapshotUndo(actionName: "Add Task")
        let item = TaskItem(title: "New Task")

        if let parent = parent(of: task),
           let index = parent.children.firstIndex(where: { $0.id == task.id }) {
            parent.children.insert(item, at: index + 1)
            parent.isExpanded = true
        } else if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.insert(item, at: index + 1)
        } else {
            tasks.insert(item, at: 0)
        }

        save()
        return item
    }

    func addChild(to parent: TaskItem) -> TaskItem {
        if let existingParent = self.parent(of: parent) {
            return addSibling(after: parent)
        }

        registerSnapshotUndo(actionName: "Add Subtask")
        let item = TaskItem(title: "New Subtask")
        let firstCompleted = parent.children.firstIndex(where: { $0.isCompleted }) ?? parent.children.count
        parent.children.insert(item, at: firstCompleted)
        parent.isExpanded = true
        save()
        return item
    }

    func rename(_ task: TaskItem, to title: String) {
        guard task.title != title else { return }
        registerSnapshotUndo(actionName: "Rename Task")
        task.title = title
        task.richTextData = nil
        save()
    }

    func updateText(_ task: TaskItem, title: String, richTextData: Data?) {
        guard task.title != title || task.richTextData != richTextData else { return }
        task.title = title
        task.richTextData = richTextData
        save()
    }

    func setCompleted(_ selectedTasks: [TaskItem], completed: Bool) {
        let changedTasks = selectedTasks.filter { $0.isCompleted != completed }
        guard !changedTasks.isEmpty else { return }

        registerSnapshotUndo(
            actionName: completed ? "Complete Tasks" : "Uncomplete Tasks"
        )

        for task in changedTasks {
            task.isCompleted = completed
        }

        save()
    }

    func setCompleted(_ task: TaskItem, _ completed: Bool) {
        guard task.isCompleted != completed else { return }
        registerSnapshotUndo(actionName: completed ? "Complete Task" : "Uncomplete Task")
        task.isCompleted = completed
        save()
    }

    func setExpanded(_ task: TaskItem, _ expanded: Bool) {
        guard task.isExpanded != expanded else { return }
        registerSnapshotUndo(actionName: expanded ? "Expand Task" : "Collapse Task")
        task.isExpanded = expanded
        save()
    }

    func delete(_ selectedTasks: [TaskItem]) {
        guard !selectedTasks.isEmpty else { return }

        registerSnapshotUndo(
            actionName: selectedTasks.count == 1 ? "Delete Task" : "Delete Tasks"
        )

        let selectedIDs = Set(selectedTasks.map(\.id))
        tasks = removingTasks(withIDs: selectedIDs, from: tasks)
        save()
    }

    private func removingTasks(
        withIDs ids: Set<UUID>,
        from items: [TaskItem]
    ) -> [TaskItem] {
        items.compactMap { item in
            guard !ids.contains(item.id) else { return nil }
            item.children = removingTasks(withIDs: ids, from: item.children)
            return item
        }
    }

    func delete(_ target: TaskItem) {
        registerSnapshotUndo(actionName: "Delete Task")
        _ = remove(target, from: &tasks)
        save()
    }

    func task(withID id: UUID) -> TaskItem? {
        find(id, in: tasks)
    }

    func parent(of target: TaskItem) -> TaskItem? {
        findParent(of: target, in: tasks)
    }

    private func findParent(of target: TaskItem, in items: [TaskItem]) -> TaskItem? {
        for item in items {
            if item.children.contains(where: { $0.id == target.id }) {
                return item
            }

            if let parent = findParent(of: target, in: item.children) {
                return parent
            }
        }

        return nil
    }

    func contains(_ possibleDescendant: TaskItem, inside possibleAncestor: TaskItem) -> Bool {
        if possibleAncestor === possibleDescendant { return true }
        for child in possibleAncestor.children {
            if contains(possibleDescendant, inside: child) { return true }
        }
        return false
    }

    func move(
        _ selectedTasks: [TaskItem],
        toParent parent: TaskItem?,
        at requestedIndex: Int
    ) {
        guard !selectedTasks.isEmpty else { return }

        let selectedIDs = Set(selectedTasks.map(\.id))
        let movableTasks = selectedTasks.filter { task in
            var currentParent = self.parent(of: task)
            while let ancestor = currentParent {
                if selectedIDs.contains(ancestor.id) {
                    return false
                }
                currentParent = self.parent(of: ancestor)
            }
            return true
        }

        guard !movableTasks.isEmpty else { return }

        let normalizedParent: TaskItem?
        if let parent, let rootParent = self.parent(of: parent) {
            normalizedParent = rootParent
        } else {
            normalizedParent = parent
        }

        if let normalizedParent,
           movableTasks.contains(where: {
               contains(normalizedParent, inside: $0)
           }) {
            return
        }

        var adjustedIndex = requestedIndex
        if let parent = normalizedParent {
            for task in movableTasks {
                if self.parent(of: task)?.id == parent.id,
                   let oldIndex = parent.children.firstIndex(where: { $0.id == task.id }),
                   oldIndex < requestedIndex {
                    adjustedIndex -= 1
                }
            }
        } else {
            for task in movableTasks {
                if self.parent(of: task) == nil,
                   let oldIndex = tasks.firstIndex(where: { $0.id == task.id }),
                   oldIndex < requestedIndex {
                    adjustedIndex -= 1
                }
            }
        }

        registerSnapshotUndo(
            actionName: movableTasks.count == 1 ? "Move Task" : "Move Tasks"
        )

        for task in movableTasks {
            _ = remove(task, from: &tasks)
        }

        if let parent = normalizedParent {
            let index = max(0, min(adjustedIndex, parent.children.count))
            parent.children.insert(contentsOf: movableTasks, at: index)
            parent.isExpanded = true
        } else {
            let index = max(0, min(adjustedIndex, tasks.count))
            tasks.insert(contentsOf: movableTasks, at: index)
        }

        moveCompletedToBottom(registerUndo: false)
        save()
    }

    func move(_ task: TaskItem, toParent parent: TaskItem?, at requestedIndex: Int) {
        let normalizedParent: TaskItem?
        if let parent, let rootParent = self.parent(of: parent) {
            normalizedParent = rootParent
        } else {
            normalizedParent = parent
        }

        if let normalizedParent, contains(normalizedParent, inside: task) { return }

        registerSnapshotUndo(actionName: "Move Task")
        _ = remove(task, from: &tasks)

        if let parent = normalizedParent {
            let index = max(0, min(requestedIndex, parent.children.count))
            parent.children.insert(task, at: index)
            parent.isExpanded = true
        } else {
            let index = max(0, min(requestedIndex, tasks.count))
            tasks.insert(task, at: index)
        }

        moveCompletedToBottom(registerUndo: false)
        save()
    }

    func moveTaskToAbsoluteBottom(_ task: TaskItem, registerUndo: Bool = true) {
        guard let currentIndex = tasks.firstIndex(where: { $0.id == task.id }),
              currentIndex != tasks.count - 1 else {
            return
        }

        if registerUndo {
            registerSnapshotUndo(actionName: "Move Task")
        }

        let movedTask = tasks.remove(at: currentIndex)
        tasks.append(movedTask)
    }

    func moveCompletedToBottom(registerUndo: Bool = true) {
        if registerUndo {
            registerSnapshotUndo(actionName: "Reorder Completed Tasks")
        }
        reorderCompleted(in: &tasks)
    }

    func performUndo() {
        undoManager.undo()
    }

    func performRedo() {
        undoManager.redo()
    }

    private func registerSnapshotUndo(actionName: String) {
        guard !isRestoringSnapshot,
              let snapshot = try? encoder.encode(tasks) else { return }

        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(snapshot, inverseActionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restoreSnapshot(_ snapshot: Data, inverseActionName: String) {
        guard let current = try? encoder.encode(tasks),
              let restored = try? decoder.decode([TaskItem].self, from: snapshot) else {
            return
        }

        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(current, inverseActionName: inverseActionName)
        }
        undoManager.setActionName(inverseActionName)

        isRestoringSnapshot = true
        tasks = restored
        isRestoringSnapshot = false
        save()
        NotificationCenter.default.post(name: .tinyTasksStoreDidChange, object: self)
    }

    private func reorderCompleted(in items: inout [TaskItem]) {
        for item in items {
            reorderCompleted(in: &item.children)
        }
        let active = items.filter { !$0.isCompleted }
        let completed = items.filter { $0.isCompleted }
        items = active + completed
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: backupsDirectory,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: databaseURL.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let backup = backupsDirectory.appendingPathComponent(
                    "tasks_\(formatter.string(from: Date())).json"
                )
                try? FileManager.default.copyItem(at: databaseURL, to: backup)
                trimBackups()
            }

            let data = try encoder.encode(tasks)
            try data.write(to: databaseURL, options: .atomic)
        } catch {
            NSLog("TinyTasks save failed: \(error)")
        }
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                tasks = [TaskItem(title: "My Tasks")]
                return
            }
            let data = try Data(contentsOf: databaseURL)
            tasks = try decoder.decode([TaskItem].self, from: data)
        } catch {
            NSLog("TinyTasks load failed: \(error)")
            tasks = [TaskItem(title: "Recovered List")]
        }
    }

    private func find(_ id: UUID, in items: [TaskItem]) -> TaskItem? {
        for item in items {
            if item.id == id { return item }
            if let found = find(id, in: item.children) { return found }
        }
        return nil
    }

    private func remove(_ target: TaskItem, from items: inout [TaskItem]) -> Bool {
        if let index = items.firstIndex(where: { $0 === target }) {
            items.remove(at: index)
            return true
        }
        for item in items {
            if remove(target, from: &item.children) {
                return true
            }
        }
        return false
    }

    private func trimBackups() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = urls.sorted {
            let a = (try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return a > b
        }

        for url in sorted.dropFirst(30) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension Notification.Name {
    static let tinyTasksStoreDidChange = Notification.Name("TinyTasksStoreDidChange")
}
