import Foundation

struct FlowSubtask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var done: Bool
}

struct FlowTaskList: Identifiable, Codable, Hashable {
    let id: String
    var name: String
}

struct FlowTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var dueAt: String?
    var category: String
    var estimate: Int
    var done: Bool
    var listId: String
    var details: String
    var deadline: Date?
    var scheduledAt: Date?
    var subtasks: [FlowSubtask]

    init(
        id: String,
        title: String,
        dueAt: String? = nil,
        category: String = "Work",
        estimate: Int = 25,
        done: Bool = false,
        listId: String = "inbox",
        details: String = "",
        deadline: Date? = nil,
        scheduledAt: Date? = nil,
        subtasks: [FlowSubtask] = []
    ) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.category = category
        self.estimate = estimate
        self.done = done
        self.listId = listId
        self.details = details
        self.deadline = deadline
        self.scheduledAt = scheduledAt
        self.subtasks = subtasks
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, dueAt, category, estimate, done, listId, details, deadline, scheduledAt, subtasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Work"
        estimate = try container.decodeIfPresent(Int.self, forKey: .estimate) ?? 25
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        listId = try container.decodeIfPresent(String.self, forKey: .listId) ?? "inbox"
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
        subtasks = try container.decodeIfPresent([FlowSubtask].self, forKey: .subtasks) ?? []
    }
}

struct FlowEvent: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var startsAt: Date
    var durationMinutes: Int
    var category: String
    var isAllDay: Bool

    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    init(id: String, title: String, startsAt: Date, durationMinutes: Int, category: String, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.category = category
        self.isAllDay = isAllDay
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startsAt, durationMinutes, category, isAllDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        category = try container.decode(String.self, forKey: .category)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
    }
}

enum FocusMode: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case stopwatch = "Stopwatch"
    var id: String { rawValue }
}

@MainActor
final class FlowtimeStore: ObservableObject {
    @Published private(set) var tasks: [FlowTask]
    @Published private(set) var taskLists: [FlowTaskList]
    @Published private(set) var events: [FlowEvent]
    @Published private(set) var categories: [String]
    @Published var selectedDate = Date()
    @Published var focusMode: FocusMode = .timer
    @Published var focusSeconds = 3_000
    @Published var timerTargetSeconds = 3_000
    @Published var isFocusing = false
    @Published private(set) var selectedFocusTaskId: String?
    @Published private(set) var focusLabel = ""
    @Published var weeklyFocusSeconds = 18 * 3_600 + 24 * 60
    @Published var sessionCount = 14

    private var ticker: Timer?
    private let taskStorageKey = "flowtime.tasks.v1"
    private let taskListStorageKey = "flowtime.task-lists.v1"
    private let eventStorageKey = "flowtime.events.v1"
    private let categoryStorageKey = "flowtime.categories.v1"

    init() {
        var initialTaskLists: [FlowTaskList]
        if let data = UserDefaults.standard.data(forKey: taskListStorageKey),
           let savedLists = try? JSONDecoder().decode([FlowTaskList].self, from: data),
           !savedLists.isEmpty {
            initialTaskLists = savedLists
        } else {
            initialTaskLists = [FlowTaskList(id: "inbox", name: "Inbox")]
        }
        if !initialTaskLists.contains(where: { $0.id == "inbox" }) {
            initialTaskLists.insert(FlowTaskList(id: "inbox", name: "Inbox"), at: 0)
        }
        taskLists = initialTaskLists

        if let savedCategories = UserDefaults.standard.stringArray(forKey: categoryStorageKey),
           !savedCategories.isEmpty {
            categories = savedCategories
        } else {
            categories = ["Work", "Personal", "Focus time"]
        }

        if let data = UserDefaults.standard.data(forKey: taskStorageKey),
           let savedTasks = try? JSONDecoder().decode([FlowTask].self, from: data) {
            tasks = savedTasks
        } else {
            tasks = [
                .init(id: "t1", title: "Review project brief", dueAt: "Today", category: "Work", estimate: 10, done: false),
                .init(id: "t2", title: "Book dentist", dueAt: "Today", category: "Personal", estimate: 5, done: false),
                .init(id: "t3", title: "Prepare weekly notes", dueAt: "Tomorrow", category: "Work", estimate: 30, done: false)
            ]
        }

        if let data = UserDefaults.standard.data(forKey: eventStorageKey),
           let savedEvents = try? JSONDecoder().decode([FlowEvent].self, from: data) {
            events = savedEvents
        } else {
            let calendar = Calendar.current
            let today = Date()
            func time(_ hour: Int, _ minute: Int) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
            }
            events = [
                .init(id: "e1", title: "Product strategy", startsAt: time(9, 0), durationMinutes: 60, category: "Work"),
                .init(id: "e2", title: "Morning run", startsAt: time(10, 30), durationMinutes: 45, category: "Personal"),
                .init(id: "e3", title: "Deep work", startsAt: time(13, 0), durationMinutes: 120, category: "Focus time"),
                .init(id: "e4", title: "Team sync", startsAt: time(16, 0), durationMinutes: 45, category: "Work")
            ]
        }
    }

    var displayedSeconds: Int { focusSeconds }

    var focusProgress: Double {
        if focusMode == .timer {
            guard timerTargetSeconds > 0 else { return 0 }
            return min(1, max(0, Double(focusSeconds) / Double(timerTargetSeconds)))
        }
        return min(1, Double(focusSeconds % 3_600) / 3_600)
    }

    func events(on date: Date) -> [FlowEvent] {
        events.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: date) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func addEvent(title: String, date: Date, startTime: Date, durationMinutes: Int, category: String, isAllDay: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let calendar = Calendar.current
        let timeParts = calendar.dateComponents([.hour, .minute], from: startTime)
        var dayParts = calendar.dateComponents([.year, .month, .day], from: date)
        dayParts.hour = timeParts.hour
        dayParts.minute = timeParts.minute
        let event = FlowEvent(
            id: UUID().uuidString,
            title: cleanTitle,
            startsAt: isAllDay ? calendar.startOfDay(for: date) : (calendar.date(from: dayParts) ?? date),
            durationMinutes: isAllDay ? 24 * 60 : durationMinutes,
            category: category,
            isAllDay: isAllDay
        )
        events.append(event)
        persistEvents()
        Task { try? await FlowtimeAPI.shared.sync(event: event) }
    }

    func delete(_ event: FlowEvent) {
        events.removeAll { $0.id == event.id }
        persistEvents()
    }

    func addCategory(_ name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !categories.contains(where: { $0.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) else { return }
        categories.append(cleanName)
        categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persistCategories()
        Task { try? await FlowtimeAPI.shared.syncCategory(cleanName) }
    }

    func deleteCategory(_ category: String) {
        guard categories.contains(category) else { return }
        var remaining = categories.filter { $0 != category }
        if remaining.isEmpty { remaining = ["Uncategorized"] }
        let fallback = remaining.first ?? "Uncategorized"
        categories = remaining

        for index in events.indices where events[index].category == category {
            events[index].category = fallback
        }
        persistCategories()
        persistEvents()

        let changedEvents = events.filter { $0.category == fallback }
        Task {
            for event in changedEvents { try? await FlowtimeAPI.shared.sync(event: event) }
            try? await FlowtimeAPI.shared.deleteCategory(category)
        }
    }

    func toggle(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].done.toggle()
        let updatedTask = tasks[index]
        if updatedTask.done, selectedFocusTaskId == updatedTask.id {
            selectFocusTask(nil)
        }
        persistTasks()
        Task { try? await FlowtimeAPI.shared.sync(task: updatedTask) }
    }

    func addTask(
        title: String,
        listId: String,
        details: String,
        estimate: Int,
        deadline: Date?,
        scheduledAt: Date?,
        subtasks: [FlowSubtask]
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let task = FlowTask(
            id: UUID().uuidString,
            title: cleanTitle,
            category: "Uncategorized",
            estimate: estimate,
            listId: taskLists.contains(where: { $0.id == listId }) ? listId : (taskLists.first?.id ?? "inbox"),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: deadline,
            scheduledAt: scheduledAt,
            subtasks: subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        tasks.insert(task, at: 0)
        persistTasks()
        Task { try? await FlowtimeAPI.shared.sync(task: task) }
    }

    func updateTask(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var cleanTask = task
        cleanTask.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.details = task.details.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.subtasks = task.subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleanTask.title.isEmpty else { return }
        tasks[index] = cleanTask
        if selectedFocusTaskId == cleanTask.id {
            focusLabel = cleanTask.title
            if !isFocusing {
                timerTargetSeconds = max(60, cleanTask.estimate * 60)
                if focusMode == .timer { focusSeconds = timerTargetSeconds }
            }
        }
        persistTasks()
        Task { try? await FlowtimeAPI.shared.sync(task: cleanTask) }
    }

    func addTaskList(_ name: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !taskLists.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) else { return nil }
        let list = FlowTaskList(id: UUID().uuidString, name: cleanName)
        taskLists.append(list)
        persistTaskLists()
        Task { try? await FlowtimeAPI.shared.sync(taskList: list) }
        return list.id
    }

    func deleteTaskList(_ list: FlowTaskList) {
        guard taskLists.count > 1, let fallback = taskLists.first(where: { $0.id != list.id }) else { return }
        taskLists.removeAll { $0.id == list.id }
        let changedTasks = tasks.indices.filter { tasks[$0].listId == list.id }
        for index in changedTasks { tasks[index].listId = fallback.id }
        persistTaskLists()
        persistTasks()
        let updatedTasks = changedTasks.map { tasks[$0] }
        Task {
            for task in updatedTasks { try? await FlowtimeAPI.shared.sync(task: task) }
            try? await FlowtimeAPI.shared.deleteTaskList(list)
        }
    }

    func delete(_ task: FlowTask) {
        tasks.removeAll { $0.id == task.id }
        if selectedFocusTaskId == task.id { selectFocusTask(nil) }
        persistTasks()
    }

    func delete(at offsets: IndexSet, from visibleTasks: [FlowTask]) {
        let ids = offsets.map { visibleTasks[$0].id }
        tasks.removeAll { ids.contains($0.id) }
        if let selectedFocusTaskId, ids.contains(selectedFocusTaskId) { selectFocusTask(nil) }
        persistTasks()
    }

    func selectFocusTask(_ id: String?) {
        pauseFocus()
        guard let id, let task = tasks.first(where: { $0.id == id && !$0.done }) else {
            selectedFocusTaskId = nil
            focusLabel = ""
            return
        }
        selectedFocusTaskId = id
        focusLabel = task.title
        focusMode = .timer
        timerTargetSeconds = max(60, task.estimate * 60)
        focusSeconds = timerTargetSeconds
    }

    func setFocusMode(_ mode: FocusMode) {
        pauseFocus()
        focusMode = mode
        focusSeconds = mode == .timer ? timerTargetSeconds : 0
    }

    func setTimerPreset(minutes: Int) {
        pauseFocus()
        timerTargetSeconds = minutes * 60
        focusSeconds = timerTargetSeconds
    }

    func toggleFocus() {
        guard selectedFocusTaskId != nil else { return }
        if isFocusing {
            pauseFocus()
        } else {
            if focusMode == .timer && focusSeconds == 0 { focusSeconds = timerTargetSeconds }
            isFocusing = true
            startTicker()
        }
    }

    func pauseFocus() {
        isFocusing = false
        ticker?.invalidate()
        ticker = nil
    }

    func resetFocus() {
        pauseFocus()
        focusSeconds = focusMode == .timer ? timerTargetSeconds : 0
    }

    func finishFocus() {
        let duration = focusMode == .timer ? timerTargetSeconds - focusSeconds : focusSeconds
        pauseFocus()
        guard duration > 0 else {
            resetFocus()
            return
        }
        weeklyFocusSeconds += duration
        sessionCount += 1
        let completedLabel = focusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            try? await FlowtimeAPI.shared.logSession(
                label: completedLabel.isEmpty ? "Focus" : completedLabel,
                mode: focusMode,
                duration: duration
            )
        }
        focusSeconds = focusMode == .timer ? timerTargetSeconds : 0
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    private func tick() {
        guard isFocusing else { return }
        if focusMode == .timer {
            focusSeconds = max(0, focusSeconds - 1)
            if focusSeconds == 0 { finishFocus() }
        } else {
            focusSeconds += 1
        }
    }

    private func persistTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: taskStorageKey)
    }

    private func persistTaskLists() {
        guard let data = try? JSONEncoder().encode(taskLists) else { return }
        UserDefaults.standard.set(data, forKey: taskListStorageKey)
    }

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: eventStorageKey)
    }

    private func persistCategories() {
        UserDefaults.standard.set(categories, forKey: categoryStorageKey)
    }
}
