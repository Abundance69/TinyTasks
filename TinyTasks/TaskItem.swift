import Foundation

final class TaskItem: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isExpanded: Bool
    var children: [TaskItem]

    init(
        id: UUID = UUID(),
        title: String = "",
        isCompleted: Bool = false,
        isExpanded: Bool = true,
        children: [TaskItem] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isExpanded = isExpanded
        self.children = children
    }
}
