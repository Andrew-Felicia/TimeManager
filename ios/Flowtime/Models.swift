import Foundation
import UIKit
import UserNotifications

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

struct StopwatchLap: Identifiable, Codable, Hashable {
    let id: UUID
    let number: Int
    let duration: TimeInterval
    let totalElapsed: TimeInterval
}

enum TimerEndAlert: String, CaseIterable, Identifiable, Codable {
    case defaultSound = "Default"
    case silent = "Silent"

    var id: String { rawValue }
}

enum TimerNotificationConstants {
    static let categoryIdentifier = "FLOWTIME_TIMER_ALARM"
    static let requestIdentifierPrefix = "flowtime.timer.alarm"
    static let stopRequestStorageKey = "flowtime.timer.stop-requested"

    static var requestIdentifiers: [String] {
        ["\(requestIdentifierPrefix).0"]
    }

    static var allRequestIdentifiers: [String] {
        requestIdentifiers + ["flowtime.timer.completed"]
    }
}

extension Notification.Name {
    static let flowtimeStopTimerAlarm = Notification.Name("flowtime.stop-timer-alarm")
}

private struct PersistedTimerState: Codable {
    let targetSeconds: Int
    let remainingSeconds: Int
    let endDate: Date?
    let isRunning: Bool
    let label: String
    let selectedTaskId: String?
    let endAlert: TimerEndAlert?
    let isRinging: Bool?
}

private struct PersistedStopwatchState: Codable {
    let accumulatedTime: TimeInterval
    let startDate: Date?
    let isRunning: Bool
    let laps: [StopwatchLap]
}

private struct PersistedFocusSession: Codable {
    let completedAt: Date
    let durationSeconds: Int
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
    @Published private(set) var timerEndAlert: TimerEndAlert = .defaultSound
    @Published private(set) var timerIsRinging = false
    @Published private(set) var stopwatchIsRunning = false
    @Published private(set) var stopwatchLaps: [StopwatchLap] = []
    @Published var weeklyFocusSeconds = 0
    @Published var sessionCount = 0

    private var ticker: Timer?
    private var savedTimerSeconds = 3_000
    private var timerIsRunning = false
    private var timerEndDate: Date?
    private var stopwatchAccumulatedTime: TimeInterval = 0
    private var stopwatchStartDate: Date?
    private var focusSessions: [PersistedFocusSession] = []
    private let taskStorageKey = "flowtime.tasks.v1"
    private let taskListStorageKey = "flowtime.task-lists.v1"
    private let eventStorageKey = "flowtime.events.v1"
    private let categoryStorageKey = "flowtime.categories.v1"
    private let timerStorageKey = "flowtime.timer.v1"
    private let stopwatchStorageKey = "flowtime.stopwatch.v1"
    private let focusSessionStorageKey = "flowtime.focus-sessions.v1"

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

        restoreFocusSessions()
        restoreTimerState()
        restoreStopwatchState()
    }

    var displayedSeconds: Int { focusSeconds }
    var isAnyFocusRunning: Bool { timerIsRunning || stopwatchIsRunning }
    var timerHasStarted: Bool { savedTimerSeconds < timerTargetSeconds }
    var timerExpectedEndDate: Date? { timerIsRunning ? timerEndDate : nil }
    var stopwatchHasStarted: Bool {
        stopwatchIsRunning || stopwatchAccumulatedTime > 0 || !stopwatchLaps.isEmpty
    }

    func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        guard stopwatchIsRunning, let stopwatchStartDate else { return stopwatchAccumulatedTime }
        return max(0, stopwatchAccumulatedTime + date.timeIntervalSince(stopwatchStartDate))
    }

    func stopwatchCurrentLapElapsed(at date: Date = Date()) -> TimeInterval {
        max(0, stopwatchElapsed(at: date) - (stopwatchLaps.last?.totalElapsed ?? 0))
    }

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
    }

    func toggle(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].done.toggle()
        let updatedTask = tasks[index]
        if updatedTask.done, selectedFocusTaskId == updatedTask.id {
            selectFocusTask(nil)
        }
        persistTasks()
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
            if !timerIsRunning {
                timerTargetSeconds = max(60, cleanTask.estimate * 60)
                savedTimerSeconds = timerTargetSeconds
                if focusMode == .timer { focusSeconds = savedTimerSeconds }
            }
        }
        persistTasks()
    }

    func addTaskList(_ name: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !taskLists.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) else { return nil }
        let list = FlowTaskList(id: UUID().uuidString, name: cleanName)
        taskLists.append(list)
        persistTaskLists()
        return list.id
    }

    func deleteTaskList(_ list: FlowTaskList) {
        guard taskLists.count > 1, let fallback = taskLists.first(where: { $0.id != list.id }) else { return }
        taskLists.removeAll { $0.id == list.id }
        let changedTasks = tasks.indices.filter { tasks[$0].listId == list.id }
        for index in changedTasks { tasks[index].listId = fallback.id }
        persistTaskLists()
        persistTasks()
    }

    func delete(_ task: FlowTask) {
        tasks.removeAll { $0.id == task.id }
        if selectedFocusTaskId == task.id { selectFocusTask(nil) }
        persistTasks()
    }

    func delete(at offsets: IndexSet, from visibleTasks: [FlowTask]) {
        let deletedTasks = offsets.map { visibleTasks[$0] }
        let ids = deletedTasks.map(\.id)
        tasks.removeAll { ids.contains($0.id) }
        if let selectedFocusTaskId, ids.contains(selectedFocusTaskId) { selectFocusTask(nil) }
        persistTasks()
    }

    func selectFocusTask(_ id: String?) {
        stopTimerForTaskSelection()
        guard let id, let task = tasks.first(where: { $0.id == id && !$0.done }) else {
            selectedFocusTaskId = nil
            focusLabel = ""
            persistTimerState()
            return
        }
        selectedFocusTaskId = id
        focusLabel = task.title
        focusMode = .timer
        timerTargetSeconds = max(60, task.estimate * 60)
        focusSeconds = timerTargetSeconds
        savedTimerSeconds = timerTargetSeconds
        persistTimerState()
    }

    func setFocusLabel(_ label: String) {
        selectedFocusTaskId = nil
        focusLabel = label
        persistTimerState()
    }

    func setTimerEndAlert(_ alert: TimerEndAlert) {
        guard timerEndAlert != alert else { return }
        timerEndAlert = alert
        persistTimerState()
        if timerIsRunning {
            cancelTimerNotification()
            scheduleTimerNotification()
        } else if timerIsRinging, alert == .silent {
            cancelTimerNotification()
        }
    }

    func setFocusMode(_ mode: FocusMode) {
        guard mode != focusMode else { return }
        saveDisplayedFocusTime()
        focusMode = mode
        refreshSelectedFocusState()
    }

    func setTimerPreset(minutes: Int) {
        setTimerDuration(seconds: minutes * 60)
    }

    func setTimerDuration(seconds: Int) {
        pauseFocus()
        timerIsRinging = false
        timerTargetSeconds = max(1, seconds)
        focusSeconds = timerTargetSeconds
        savedTimerSeconds = timerTargetSeconds
        timerEndDate = nil
        cancelTimerNotification()
        persistTimerState()
    }

    func toggleFocus() {
        if focusMode == .stopwatch {
            toggleStopwatch()
            return
        }
        if timerIsRinging {
            stopTimerAlarm()
            return
        }
        if timerIsRunning {
            reconcileTimer()
            timerEndDate = nil
            timerIsRunning = false
            cancelTimerNotification()
        } else {
            if savedTimerSeconds == 0 {
                savedTimerSeconds = timerTargetSeconds
            }
            if focusLabel.isEmpty { focusLabel = "Focus" }
            timerIsRunning = true
            timerEndDate = Date().addingTimeInterval(TimeInterval(savedTimerSeconds))
            scheduleTimerNotification()
        }
        refreshSelectedFocusState()
        updateTicker()
        persistTimerState()
    }

    func toggleStopwatch() {
        if stopwatchIsRunning {
            pauseStopwatch()
        } else {
            stopwatchStartDate = Date()
            stopwatchIsRunning = true
            refreshSelectedFocusState()
            persistStopwatchState()
        }
    }

    func recordStopwatchLap() {
        guard stopwatchIsRunning else { return }
        let total = stopwatchElapsed()
        let lapDuration = max(0, total - (stopwatchLaps.last?.totalElapsed ?? 0))
        stopwatchLaps.append(
            StopwatchLap(
                id: UUID(),
                number: stopwatchLaps.count + 1,
                duration: lapDuration,
                totalElapsed: total
            )
        )
        persistStopwatchState()
    }

    func resetStopwatch() {
        guard !stopwatchIsRunning else { return }
        let completedDuration = Int(stopwatchAccumulatedTime.rounded(.down))
        if completedDuration > 0 {
            recordFocusSession(duration: completedDuration)
        }
        stopwatchAccumulatedTime = 0
        stopwatchStartDate = nil
        stopwatchLaps = []
        refreshSelectedFocusState()
        persistStopwatchState()
    }

    func pauseFocus() {
        if focusMode == .timer {
            if timerIsRunning {
                reconcileTimer()
                timerEndDate = nil
                timerIsRunning = false
                cancelTimerNotification()
            }
            persistTimerState()
        } else if stopwatchIsRunning {
            pauseStopwatch()
        }
        refreshSelectedFocusState()
        updateTicker()
    }

    func resetFocus() {
        if focusMode == .timer {
            pauseFocus()
            timerIsRinging = false
            cancelTimerNotification()
            savedTimerSeconds = timerTargetSeconds
            focusSeconds = savedTimerSeconds
            persistTimerState()
        } else {
            if stopwatchIsRunning { pauseStopwatch() }
            resetStopwatch()
        }
    }

    func finishFocus() {
        saveDisplayedFocusTime()
        finishFocus(mode: focusMode)
    }

    private func finishFocus(mode: FocusMode, preserveCompletionNotification: Bool = false) {
        if mode == .stopwatch, stopwatchIsRunning {
            pauseStopwatch()
        }
        let duration = mode == .timer
            ? timerTargetSeconds - savedTimerSeconds
            : Int(stopwatchAccumulatedTime.rounded(.down))
        if mode == .timer {
            timerIsRunning = false
            timerEndDate = nil
            if preserveCompletionNotification {
                timerIsRinging = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                timerIsRinging = false
                cancelTimerNotification()
            }
        }
        guard duration > 0 else {
            resetFocusValue(for: mode)
            refreshSelectedFocusState()
            updateTicker()
            if mode == .timer { persistTimerState() } else { persistStopwatchState() }
            return
        }
        recordFocusSession(duration: duration)
        resetFocusValue(for: mode)
        refreshSelectedFocusState()
        updateTicker()
        if mode == .timer { persistTimerState() } else { persistStopwatchState() }
    }

    private func saveDisplayedFocusTime() {
        if focusMode == .timer {
            if timerIsRunning { reconcileTimer() }
        } else {
            reconcileStopwatch()
        }
    }

    private func resetFocusValue(for mode: FocusMode) {
        if mode == .timer {
            savedTimerSeconds = timerTargetSeconds
        } else {
            stopwatchAccumulatedTime = 0
            stopwatchStartDate = nil
            stopwatchIsRunning = false
            stopwatchLaps = []
        }
    }

    private func refreshSelectedFocusState() {
        focusSeconds = focusMode == .timer ? savedTimerSeconds : Int(stopwatchElapsed().rounded(.down))
        isFocusing = focusMode == .timer ? timerIsRunning : stopwatchIsRunning
    }

    private func stopTimerForTaskSelection() {
        if timerIsRunning { reconcileTimer() }
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        cancelTimerNotification()
        refreshSelectedFocusState()
        updateTicker()
        persistTimerState()
    }

    private func updateTicker() {
        if !timerIsRunning {
            ticker?.invalidate()
            ticker = nil
        } else if ticker == nil {
            startTicker()
        }
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
        guard timerIsRunning else { return }
        reconcileTimer()
    }

    func reconcileClocks() {
        if timerIsRunning { reconcileTimer() }
        if stopwatchIsRunning { reconcileStopwatch() }
        refreshSelectedFocusState()
        updateTicker()
    }

    func stopTimerAlarm() {
        if timerIsRunning { reconcileTimer() }
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        savedTimerSeconds = timerTargetSeconds
        cancelTimerNotification()
        UserDefaults.standard.removeObject(forKey: TimerNotificationConstants.stopRequestStorageKey)
        refreshSelectedFocusState()
        updateTicker()
        persistTimerState()
    }

    private func reconcileTimer(now: Date = Date()) {
        guard timerIsRunning, let timerEndDate else { return }
        savedTimerSeconds = max(0, Int(ceil(timerEndDate.timeIntervalSince(now))))
        if focusMode == .timer { focusSeconds = savedTimerSeconds }
        if savedTimerSeconds == 0 {
            finishFocus(mode: .timer, preserveCompletionNotification: true)
        } else {
            persistTimerState()
        }
    }

    private func reconcileStopwatch(now: Date = Date()) {
        guard stopwatchIsRunning else { return }
        if focusMode == .stopwatch {
            focusSeconds = Int(stopwatchElapsed(at: now).rounded(.down))
        }
    }

    private func pauseStopwatch(now: Date = Date()) {
        guard stopwatchIsRunning else { return }
        stopwatchAccumulatedTime = stopwatchElapsed(at: now)
        stopwatchStartDate = nil
        stopwatchIsRunning = false
        refreshSelectedFocusState()
        persistStopwatchState()
    }

    private func persistTimerState() {
        let state = PersistedTimerState(
            targetSeconds: timerTargetSeconds,
            remainingSeconds: savedTimerSeconds,
            endDate: timerEndDate,
            isRunning: timerIsRunning,
            label: focusLabel,
            selectedTaskId: selectedFocusTaskId,
            endAlert: timerEndAlert,
            isRinging: timerIsRinging
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: timerStorageKey)
    }

    private func restoreTimerState() {
        guard let data = UserDefaults.standard.data(forKey: timerStorageKey),
              let state = try? JSONDecoder().decode(PersistedTimerState.self, from: data) else { return }

        timerTargetSeconds = max(1, state.targetSeconds)
        savedTimerSeconds = min(max(0, state.remainingSeconds), timerTargetSeconds)
        focusLabel = state.label
        timerEndAlert = state.endAlert ?? .defaultSound
        // Older builds kept the timer blocked after its banner disappeared.
        // Completion alerts now run independently, so always restore an idle timer.
        let wasBlockedByOldRingingState = state.isRinging ?? false
        timerIsRinging = false
        if let taskId = state.selectedTaskId, tasks.contains(where: { $0.id == taskId && !$0.done }) {
            selectedFocusTaskId = taskId
        }

        if state.isRunning, let endDate = state.endDate {
            let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            if remaining > 0 {
                timerEndDate = endDate
                savedTimerSeconds = min(remaining, timerTargetSeconds)
                timerIsRunning = true
            } else {
                savedTimerSeconds = 0
                UserDefaults.standard.removeObject(forKey: timerStorageKey)
                finishFocus(mode: .timer, preserveCompletionNotification: true)
            }
        }

        if wasBlockedByOldRingingState {
            timerIsRunning = false
            timerEndDate = nil
            savedTimerSeconds = timerTargetSeconds
            cancelTimerNotification()
        }


        focusSeconds = savedTimerSeconds
        refreshSelectedFocusState()
        updateTicker()
        if wasBlockedByOldRingingState { persistTimerState() }
        if UserDefaults.standard.bool(forKey: TimerNotificationConstants.stopRequestStorageKey) {
            stopTimerAlarm()
        }
    }

    private func persistStopwatchState() {
        let state = PersistedStopwatchState(
            accumulatedTime: stopwatchAccumulatedTime,
            startDate: stopwatchStartDate,
            isRunning: stopwatchIsRunning,
            laps: stopwatchLaps
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stopwatchStorageKey)
    }

    private func restoreStopwatchState() {
        guard let data = UserDefaults.standard.data(forKey: stopwatchStorageKey),
              let state = try? JSONDecoder().decode(PersistedStopwatchState.self, from: data) else { return }

        stopwatchAccumulatedTime = max(0, state.accumulatedTime)
        stopwatchLaps = state.laps
            .filter { $0.duration >= 0 && $0.totalElapsed >= 0 }
            .sorted { $0.number < $1.number }
        if state.isRunning, let startDate = state.startDate {
            stopwatchStartDate = min(startDate, Date())
            stopwatchIsRunning = true
        } else {
            stopwatchStartDate = nil
            stopwatchIsRunning = false
        }
        refreshSelectedFocusState()
    }

    private func scheduleTimerNotification() {
        guard let timerEndDate else { return }
        let title = focusLabel.isEmpty ? "Timer" : focusLabel
        let selectedAlert = timerEndAlert
        let scheduledEndDate = timerEndDate

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            }
            guard isAuthorized else { return }
            guard timerIsRunning,
                  self.timerEndDate == scheduledEndDate,
                  timerEndAlert == selectedAlert else { return }

            center.removePendingNotificationRequests(withIdentifiers: TimerNotificationConstants.allRequestIdentifiers)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Time’s up"
            content.sound = selectedAlert == .defaultSound
                ? UNNotificationSound(named: UNNotificationSoundName(TimerAlarmSound.fileName))
                : nil
            content.categoryIdentifier = TimerNotificationConstants.categoryIdentifier
            content.threadIdentifier = TimerNotificationConstants.requestIdentifierPrefix

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, scheduledEndDate.timeIntervalSinceNow),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: TimerNotificationConstants.requestIdentifiers[0],
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func cancelTimerNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: TimerNotificationConstants.allRequestIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: TimerNotificationConstants.allRequestIdentifiers)
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

    private func restoreFocusSessions() {
        if let data = UserDefaults.standard.data(forKey: focusSessionStorageKey),
           let sessions = try? JSONDecoder().decode([PersistedFocusSession].self, from: data) {
            focusSessions = sessions
        }
        refreshFocusStats()
    }

    private func recordFocusSession(duration: Int) {
        focusSessions.append(PersistedFocusSession(completedAt: Date(), durationSeconds: duration))
        if let data = try? JSONEncoder().encode(focusSessions) {
            UserDefaults.standard.set(data, forKey: focusSessionStorageKey)
        }
        refreshFocusStats()
    }

    private func refreshFocusStats() {
        sessionCount = focusSessions.count
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        weeklyFocusSeconds = focusSessions
            .filter { $0.completedAt >= weekStart }
            .reduce(0) { $0 + $1.durationSeconds }
    }
}
