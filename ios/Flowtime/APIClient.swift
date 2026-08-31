import Foundation

actor FlowtimeAPI {
    static let shared = FlowtimeAPI()

    // Replace with the public production API after account authentication is added.
    var baseURL = URL(string: "https://flowtime.example.com")!

    func sync(task: FlowTask) async throws {
        let formatter = ISO8601DateFormatter()
        let payload = TaskSyncPayload(
            id: task.id,
            title: task.title,
            when: task.dueAt,
            category: task.category,
            estimate: task.estimate,
            done: task.done,
            listId: task.listId,
            details: task.details,
            deadline: task.deadline.map(formatter.string(from:)),
            scheduledAt: task.scheduledAt.map(formatter.string(from:)),
            subtasks: task.subtasks.map { SubtaskSyncPayload(id: $0.id, title: $0.title, done: $0.done) }
        )
        try await post(action: "upsert-task", payload: payload)
    }

    func logSession(label: String, mode: FocusMode, duration: Int) async throws {
        let payload = SessionSyncPayload(
            id: UUID().uuidString,
            label: label,
            mode: mode.rawValue.lowercased(),
            duration: duration
        )
        try await post(action: "log-session", payload: payload)
    }

    func sync(event: FlowEvent) async throws {
        let formatter = ISO8601DateFormatter()
        let payload = EventSyncPayload(
            id: event.id,
            title: event.title,
            startsAt: formatter.string(from: event.startsAt),
            endsAt: formatter.string(from: event.endsAt),
            category: event.category,
            allDay: event.isAllDay
        )
        try await post(action: "upsert-event", payload: payload)
    }

    func syncCategory(_ name: String) async throws {
        try await post(action: "upsert-category", payload: CategorySyncPayload(name: name))
    }

    func deleteCategory(_ name: String) async throws {
        try await post(action: "delete-category", payload: CategorySyncPayload(name: name))
    }

    func sync(taskList: FlowTaskList) async throws {
        try await post(action: "upsert-task-list", payload: TaskListSyncPayload(id: taskList.id, name: taskList.name))
    }

    func deleteTaskList(_ taskList: FlowTaskList) async throws {
        try await post(action: "delete-task-list", payload: TaskListSyncPayload(id: taskList.id, name: taskList.name))
    }

    private func post<Payload: Encodable>(action: String, payload: Payload) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncEnvelope(action: action, payload: payload))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct TaskSyncPayload: Encodable {
    let id: String
    let title: String
    let when: String?
    let category: String
    let estimate: Int
    let done: Bool
    let listId: String
    let details: String
    let deadline: String?
    let scheduledAt: String?
    let subtasks: [SubtaskSyncPayload]
}

private struct SubtaskSyncPayload: Encodable {
    let id: String
    let title: String
    let done: Bool
}

private struct TaskListSyncPayload: Encodable {
    let id: String
    let name: String
}

private struct SessionSyncPayload: Encodable {
    let id: String
    let label: String
    let mode: String
    let duration: Int
}

private struct EventSyncPayload: Encodable {
    let id: String
    let title: String
    let startsAt: String
    let endsAt: String
    let category: String
    let allDay: Bool
}

private struct CategorySyncPayload: Encodable {
    let name: String
}

private struct SyncEnvelope<Payload: Encodable>: Encodable {
    let action: String
    let payload: Payload
}
