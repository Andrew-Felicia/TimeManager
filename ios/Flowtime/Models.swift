import Foundation

struct FlowTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var dueAt: String?
    var category: String
    var estimate: Int
    var done: Bool
}

@MainActor
final class FlowtimeStore: ObservableObject {
    @Published var tasks: [FlowTask] = [
        .init(id: "t1", title: "Review project brief", dueAt: "Today", category: "Work", estimate: 10, done: false),
        .init(id: "t2", title: "Book dentist", dueAt: "Today", category: "Personal", estimate: 5, done: false),
        .init(id: "t3", title: "Prepare weekly notes", dueAt: "Tomorrow", category: "Work", estimate: 30, done: false)
    ]
    @Published var focusSeconds = 3_000
    @Published var isFocusing = false

    func toggle(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].done.toggle()
        Task { try? await FlowtimeAPI.shared.sync(task: tasks[index]) }
    }

    func addTask(title: String) {
        let task = FlowTask(id: UUID().uuidString, title: title, dueAt: "Today", category: "Work", estimate: 25, done: false)
        tasks.insert(task, at: 0)
        Task { try? await FlowtimeAPI.shared.sync(task: task) }
    }
}
