import Foundation

final class TaskItem: Codable {
    var id: UUID
    var title: String
    var richTextData: Data?
    var isCompleted: Bool
    var isExpanded: Bool
    var children: [TaskItem]

    init(
        id: UUID = UUID(),
        title: String = "",
        richTextData: Data? = nil,
        isCompleted: Bool = false,
        isExpanded: Bool = true,
        children: [TaskItem] = []
    ) {
        self.id = id
        self.title = title
        self.richTextData = richTextData
        self.isCompleted = isCompleted
        self.isExpanded = isExpanded
        self.children = children
    }
}
