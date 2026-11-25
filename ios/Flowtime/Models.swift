import Foundation
import UIKit
import UserNotifications

enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}

struct FlowTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var estimate: Int
    var done: Bool
    var category: String?
    var priority: TaskPriority
    var scheduledAt: Date

    init(
        id: String,
        title: String,
        estimate: Int = 25,
        done: Bool = false,
        category: String? = nil,
        priority: TaskPriority = .medium,
        scheduledAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.estimate = estimate
        self.done = done
        self.category = category
        self.priority = priority
        self.scheduledAt = Calendar.current.startOfDay(for: scheduledAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, estimate, done, category, priority, scheduledAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        estimate = min(1_439, max(1, try container.decodeIfPresent(Int.self, forKey: .estimate) ?? 25))
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        category = try container.decodeIfPresent(String.self, forKey: .category)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        let savedSchedule = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? Date()
        scheduledAt = Calendar.current.startOfDay(for: savedSchedule)
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

    var inclusiveEndDate: Date {
        guard isAllDay else { return endsAt }
        return Calendar.current.date(byAdding: .day, value: -1, to: endsAt) ?? startsAt
    }

    func occurs(on date: Date) -> Bool {
        guard let day = Calendar.current.dateInterval(of: .day, for: date) else { return false }
        return startsAt < day.end && endsAt > day.start
    }

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

enum TimerEndAlert: String, CaseIterable, Identifiable, Codable {
    case defaultSound = "Default"
    case tws = "TWS"
    case masterCaution = "Master Caution"
    case missileLaunch = "Missile Launch"
    case rwr = "RWR"

    var id: String { rawValue }

    var displayName: String {
        self == .defaultSound ? "Classic" : rawValue
    }

    var description: String {
        switch self {
        case .defaultSound: return "Alternating alarm"
        case .tws: return "Track-while-scan warning chirps"
        case .masterCaution: return "Four-beat caution warning"
        case .missileLaunch: return "Rapid launch-warning siren"
        case .rwr: return "Radar-warning receiver cadence"
        }
    }

    var soundFileName: String? {
        switch self {
        case .defaultSound: return "flowtime-alarm.wav"
        case .tws: return "flowtime-tws-v2.wav"
        case .masterCaution: return "flowtime-master-caution-v2.wav"
        case .missileLaunch: return "flowtime-missile-launch-v2.wav"
        case .rwr: return "flowtime-rwr-v2.wav"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let storedValue = try container.decode(String.self)

        switch storedValue {
        case Self.defaultSound.rawValue:
            self = .defaultSound
        case Self.tws.rawValue, "TWS Launch 2":
            self = .tws
        case Self.masterCaution.rawValue:
            self = .masterCaution
        case Self.missileLaunch.rawValue:
            self = .missileLaunch
        case Self.rwr.rawValue, "RWR Lock", "Jet Lock":
            self = .rwr
        default:
            self = .defaultSound
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
    let remainingByTask: [String: Int]?
}

struct FocusSession: Identifiable, Codable, Hashable {
    let id: String
    var completedAt: Date
    var durationSeconds: Int
    var category: String?

    init(id: String = UUID().uuidString, completedAt: Date, durationSeconds: Int, category: String?) {
        self.id = id
        self.completedAt = completedAt
        self.durationSeconds = max(0, durationSeconds)
        self.category = category
    }

    private enum CodingKeys: String, CodingKey {
        case id, completedAt, durationSeconds, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        durationSeconds = max(0, try container.decode(Int.self, forKey: .durationSeconds))
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
}

private struct FlowtimeExportArchive: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    let selectedCalendarDate: Date
    let categories: [String]
    let tasks: [FlowTask]
    let calendarEvents: [ExportedCalendarEvent]
    let insights: ExportedInsights
    let timer: ExportedTimer
    let settings: ExportedSettings
}

private struct ExportedCalendarEvent: Codable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date
    let category: String
    let isAllDay: Bool
}

private struct ExportedInsights: Codable {
    let totalFocusSeconds: Int
    let focusSessions: [FocusSession]
}

private struct ExportedTimer: Codable {
    let selectedTaskId: String?
    let isRunning: Bool
    let isRinging: Bool
    let targetSeconds: Int
    let remainingSeconds: Int
    let scheduledEndDate: Date?
    let remainingSecondsByTask: [String: Int]
}

private struct ExportedSettings: Codable {
    let appearance: String
    let timerEndAlert: TimerEndAlert
}

@MainActor
final class FlowtimeStore: ObservableObject {
    @Published private(set) var tasks: [FlowTask]
    @Published private(set) var events: [FlowEvent]
    @Published private(set) var categories: [String]
    @Published var selectedDate = Date()
    @Published private(set) var selectedFocusTaskId: String?
    @Published private(set) var timerEndAlert: TimerEndAlert = .defaultSound
    @Published private(set) var timerIsRinging = false
    @Published private(set) var timerRemainingByTask: [String: Int] = [:]
    @Published private(set) var focusSessions: [FocusSession] = []

    private var ticker: Timer?
    private var savedTimerSeconds = 0
    private var timerTargetSeconds = 0
    private var timerIsRunning = false
    private var timerEndDate: Date?
    private var focusLabel = ""
    private let taskStorageKey = "flowtime.tasks.v1"
    private let eventStorageKey = "flowtime.events.v1"
    private let categoryStorageKey = "flowtime.categories.v1"
    private let timerStorageKey = "flowtime.timer.v1"
    private let focusSessionStorageKey = "flowtime.focus-sessions.v1"

    init() {
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
                .init(id: "t1", title: "Review project brief", estimate: 10),
                .init(id: "t2", title: "Book dentist", estimate: 5),
                .init(id: "t3", title: "Prepare weekly notes", estimate: 30)
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

        // Save migration defaults so priority and scheduled day stay stable for older tasks.
        persistTasks()
        restoreFocusSessions()
        restoreTimerState()
    }

    func events(on date: Date) -> [FlowEvent] {
        events.filter { $0.occurs(on: date) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var activeTasks: [FlowTask] {
        tasks.filter { !$0.done }
    }

    func addEvent(
        startDate: Date,
        endDate: Date,
        category: String
    ) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let requestedEnd = calendar.startOfDay(for: endDate)
        let normalizedEnd = max(normalizedStart, requestedEnd)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: normalizedEnd)
            ?? normalizedEnd.addingTimeInterval(24 * 60 * 60)
        let durationMinutes = max(24 * 60, Int(endExclusive.timeIntervalSince(normalizedStart) / 60))
        let event = FlowEvent(
            id: UUID().uuidString,
            title: category,
            startsAt: normalizedStart,
            durationMinutes: durationMinutes,
            category: category,
            isAllDay: true
        )
        events.append(event)
        persistEvents()
    }

    func exportData(appearance: String) throws -> Data {
        let archive = FlowtimeExportArchive(
            formatVersion: 1,
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            selectedCalendarDate: selectedDate,
            categories: categories,
            tasks: tasks,
            calendarEvents: events.map { event in
                ExportedCalendarEvent(
                    id: event.id,
                    title: event.title,
                    startsAt: event.startsAt,
                    endsAt: event.endsAt,
                    category: event.category,
                    isAllDay: event.isAllDay
                )
            },
            insights: ExportedInsights(
                totalFocusSeconds: totalFocusSeconds,
                focusSessions: focusSessions
            ),
            timer: ExportedTimer(
                selectedTaskId: selectedFocusTaskId,
                isRunning: timerIsRunning,
                isRinging: timerIsRinging,
                targetSeconds: timerTargetSeconds,
                remainingSeconds: savedTimerSeconds,
                scheduledEndDate: timerEndDate,
                remainingSecondsByTask: timerRemainingByTask
            ),
            settings: ExportedSettings(
                appearance: appearance,
                timerEndAlert: timerEndAlert
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(archive)
    }

    func importData(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(FlowtimeExportArchive.self, from: data)
        guard archive.formatVersion == 1 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        categories = archive.categories.isEmpty ? ["Uncategorized"] : archive.categories
        tasks = archive.tasks
        events = archive.calendarEvents.map { event in
            FlowEvent(
                id: event.id,
                title: event.title,
                startsAt: event.startsAt,
                durationMinutes: max(1, Int(ceil(event.endsAt.timeIntervalSince(event.startsAt) / 60))),
                category: event.category,
                isAllDay: event.isAllDay
            )
        }
        focusSessions = archive.insights.focusSessions
        selectedDate = archive.selectedCalendarDate
        timerEndAlert = archive.settings.timerEndAlert

        let activeTasksById = Dictionary(uniqueKeysWithValues: activeTasks.map { ($0.id, $0) })
        timerRemainingByTask = archive.timer.remainingSecondsByTask.reduce(into: [:]) { result, entry in
            guard let task = activeTasksById[entry.key] else { return }
            result[entry.key] = min(task.estimate * 60, max(0, entry.value))
        }
        for task in activeTasks where timerRemainingByTask[task.id] == nil {
            timerRemainingByTask[task.id] = task.estimate * 60
        }

        if let selectedId = archive.timer.selectedTaskId,
           let selectedTask = activeTasksById[selectedId] {
            selectedFocusTaskId = selectedId
            focusLabel = selectedTask.title
            timerTargetSeconds = selectedTask.estimate * 60
            savedTimerSeconds = min(
                timerTargetSeconds,
                max(0, timerRemainingByTask[selectedId] ?? archive.timer.remainingSeconds)
            )
            timerRemainingByTask[selectedId] = savedTimerSeconds
        } else {
            selectedFocusTaskId = nil
            focusLabel = ""
            timerTargetSeconds = 0
            savedTimerSeconds = 0
        }
        timerIsRunning = false
        timerIsRinging = false
        timerEndDate = nil
        cancelTimerNotification()
        updateTicker()

        persistCategories()
        persistTasks()
        persistEvents()
        persistFocusSessions()
        persistTimerState()

        return archive.settings.appearance == "Light" ? "Light" : "Dark"
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
        tasks = tasks.map { task in
            guard task.category == category else { return task }
            var updatedTask = task
            updatedTask.category = nil
            return updatedTask
        }
        persistCategories()
        persistEvents()
        persistTasks()
    }

    func toggle(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updatedTasks = tasks
        updatedTasks[index].done.toggle()
        tasks = updatedTasks
        let updatedTask = updatedTasks[index]
        if updatedTask.done { removeTimer(for: updatedTask.id) }
        persistTasks()
    }

    func addTask(
        title: String,
        estimate: Int,
        category: String?,
        priority: TaskPriority,
        scheduledAt: Date
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let task = FlowTask(
            id: UUID().uuidString,
            title: cleanTitle,
            estimate: min(1_439, max(1, estimate)),
            category: normalizedTaskCategory(category),
            priority: priority,
            scheduledAt: Calendar.current.startOfDay(for: scheduledAt)
        )
        tasks = [task] + tasks
        timerRemainingByTask[task.id] = task.estimate * 60
        persistTasks()
        persistTimerState()
    }

    func updateTask(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousTask = tasks[index]
        var cleanTask = task
        cleanTask.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.estimate = min(1_439, max(1, task.estimate))
        cleanTask.category = normalizedTaskCategory(task.category)
        cleanTask.scheduledAt = Calendar.current.startOfDay(for: task.scheduledAt)
        guard !cleanTask.title.isEmpty else { return }
        var updatedTasks = tasks
        updatedTasks[index] = cleanTask
        tasks = updatedTasks
        syncTimer(with: cleanTask, previousEstimate: previousTask.estimate)
        persistTasks()
    }

    func delete(_ task: FlowTask) {
        removeTimer(for: task.id)
        tasks.removeAll { $0.id == task.id }
        persistTasks()
    }

    func timerRemainingSeconds(for task: FlowTask) -> Int {
        let target = task.estimate * 60
        if selectedFocusTaskId == task.id {
            return min(target, max(0, savedTimerSeconds))
        }
        return min(target, max(0, timerRemainingByTask[task.id] ?? target))
    }

    func synchronizeTaskTimers() {
        let activeTaskIds = Set(activeTasks.map(\.id))
        var synchronized = timerRemainingByTask.filter { activeTaskIds.contains($0.key) }
        for task in activeTasks where synchronized[task.id] == nil {
            synchronized[task.id] = task.estimate * 60
        }
        guard synchronized != timerRemainingByTask else { return }
        timerRemainingByTask = synchronized
        persistTimerState()
    }

    func timerHasStarted(for task: FlowTask) -> Bool {
        timerRemainingSeconds(for: task) < task.estimate * 60
    }

    func timerIsRunning(for task: FlowTask) -> Bool {
        timerIsRunning && selectedFocusTaskId == task.id
    }

    func toggleTimer(for task: FlowTask) {
        guard !task.done, tasks.contains(where: { $0.id == task.id && !$0.done }) else { return }
        if timerIsRunning(for: task) {
            pauseActiveTimer()
        } else {
            startTimer(for: task)
        }
    }

    func resetTimer(for task: FlowTask) {
        let target = task.estimate * 60
        if selectedFocusTaskId == task.id {
            if timerIsRunning { reconcileTimer() }
            timerIsRunning = false
            timerEndDate = nil
            timerIsRinging = false
            cancelTimerNotification()
            timerTargetSeconds = target
            savedTimerSeconds = target
        }
        timerRemainingByTask[task.id] = target
        updateTicker()
        persistTimerState()
    }

    func setTimerEndAlert(_ alert: TimerEndAlert) {
        guard timerEndAlert != alert else { return }
        timerEndAlert = alert
        persistTimerState()
        if timerIsRunning {
            cancelTimerNotification()
            scheduleTimerNotification()
        }
    }

    private func startTimer(for task: FlowTask) {
        if timerIsRunning { pauseActiveTimer() }
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }

        let target = task.estimate * 60
        var remaining = timerRemainingByTask[task.id] ?? target
        if remaining <= 0 || remaining > target { remaining = target }

        selectedFocusTaskId = task.id
        focusLabel = task.title
        timerTargetSeconds = target
        savedTimerSeconds = remaining
        timerRemainingByTask[task.id] = remaining
        timerIsRinging = false
        timerIsRunning = true
        timerEndDate = Date().addingTimeInterval(TimeInterval(remaining))
        cancelTimerNotification()
        scheduleTimerNotification()
        updateTicker()
        persistTimerState()
    }

    private func pauseActiveTimer() {
        guard timerIsRunning else { return }
        reconcileTimer()
        guard timerIsRunning else { return }
        timerIsRunning = false
        timerEndDate = nil
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }
        cancelTimerNotification()
        updateTicker()
        persistTimerState()
    }

    private func syncTimer(with task: FlowTask, previousEstimate: Int) {
        let oldTarget = previousEstimate * 60
        let newTarget = task.estimate * 60

        if selectedFocusTaskId == task.id {
            if timerIsRunning { reconcileTimer() }
            let elapsed = max(0, oldTarget - savedTimerSeconds)
            let remaining = max(0, newTarget - elapsed)
            focusLabel = task.title
            timerTargetSeconds = newTarget
            savedTimerSeconds = remaining
            timerRemainingByTask[task.id] = remaining

            if timerIsRunning {
                if remaining == 0 {
                    finishTimer(preserveCompletionNotification: false)
                    return
                }
                timerEndDate = Date().addingTimeInterval(TimeInterval(remaining))
                cancelTimerNotification()
                scheduleTimerNotification()
            } else if remaining == 0 {
                savedTimerSeconds = newTarget
                timerRemainingByTask[task.id] = newTarget
            }
        } else if let oldRemaining = timerRemainingByTask[task.id] {
            let elapsed = max(0, oldTarget - oldRemaining)
            let remaining = max(0, newTarget - elapsed)
            timerRemainingByTask[task.id] = remaining == 0 ? newTarget : remaining
        }
        persistTimerState()
    }

    private func removeTimer(for taskId: String) {
        guard selectedFocusTaskId == taskId else {
            timerRemainingByTask.removeValue(forKey: taskId)
            persistTimerState()
            return
        }
        if timerIsRunning { reconcileTimer() }
        timerRemainingByTask.removeValue(forKey: taskId)
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        selectedFocusTaskId = nil
        focusLabel = ""
        timerTargetSeconds = 0
        savedTimerSeconds = 0
        cancelTimerNotification()
        updateTicker()
        persistTimerState()
    }

    private func finishTimer(preserveCompletionNotification: Bool) {
        let duration = max(0, timerTargetSeconds - savedTimerSeconds)
        let completedCategory = selectedFocusTaskId
            .flatMap { taskId in tasks.first(where: { $0.id == taskId }) }
            .flatMap(\.category)
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        if preserveCompletionNotification {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            cancelTimerNotification()
        }
        if duration > 0 { recordFocusSession(duration: duration, category: completedCategory) }
        savedTimerSeconds = timerTargetSeconds
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }
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
        updateTicker()
    }

    func stopTimerAlarm() {
        if timerIsRunning { reconcileTimer() }
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        savedTimerSeconds = timerTargetSeconds
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }
        cancelTimerNotification()
        UserDefaults.standard.removeObject(forKey: TimerNotificationConstants.stopRequestStorageKey)
        updateTicker()
        persistTimerState()
    }

    private func reconcileTimer(now: Date = Date()) {
        guard timerIsRunning, let timerEndDate else { return }
        savedTimerSeconds = max(0, Int(ceil(timerEndDate.timeIntervalSince(now))))
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }
        if savedTimerSeconds == 0 {
            finishTimer(preserveCompletionNotification: true)
        } else {
            persistTimerState()
        }
    }

    private func persistTimerState() {
        if let selectedFocusTaskId {
            timerRemainingByTask[selectedFocusTaskId] = savedTimerSeconds
        }
        let state = PersistedTimerState(
            targetSeconds: timerTargetSeconds,
            remainingSeconds: savedTimerSeconds,
            endDate: timerEndDate,
            isRunning: timerIsRunning,
            label: focusLabel,
            selectedTaskId: selectedFocusTaskId,
            endAlert: timerEndAlert,
            isRinging: timerIsRinging,
            remainingByTask: timerRemainingByTask
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: timerStorageKey)
    }

    private func restoreTimerState() {
        guard let data = UserDefaults.standard.data(forKey: timerStorageKey),
              let state = try? JSONDecoder().decode(PersistedTimerState.self, from: data) else { return }

        timerEndAlert = state.endAlert ?? .defaultSound
        let wasBlockedByOldRingingState = state.isRinging ?? false
        timerIsRinging = false

        let availableTasks = Dictionary(uniqueKeysWithValues: tasks.filter { !$0.done }.map { ($0.id, $0) })
        timerRemainingByTask = (state.remainingByTask ?? [:]).reduce(into: [:]) { result, entry in
            guard let task = availableTasks[entry.key] else { return }
            result[entry.key] = min(task.estimate * 60, max(0, entry.value))
        }

        guard let taskId = state.selectedTaskId, let selectedTask = availableTasks[taskId] else {
            selectedFocusTaskId = nil
            focusLabel = ""
            timerTargetSeconds = 0
            savedTimerSeconds = 0
            timerIsRunning = false
            timerEndDate = nil
            cancelTimerNotification()
            UserDefaults.standard.removeObject(forKey: TimerNotificationConstants.stopRequestStorageKey)
            updateTicker()
            persistTimerState()
            return
        }

        selectedFocusTaskId = taskId
        focusLabel = selectedTask.title
        timerTargetSeconds = selectedTask.estimate * 60
        let restoredRemaining = timerRemainingByTask[taskId] ?? state.remainingSeconds
        savedTimerSeconds = min(timerTargetSeconds, max(0, restoredRemaining))
        timerRemainingByTask[taskId] = savedTimerSeconds

        if state.isRunning, !wasBlockedByOldRingingState, let endDate = state.endDate {
            let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            if remaining > 0 {
                timerEndDate = endDate
                savedTimerSeconds = min(remaining, timerTargetSeconds)
                timerRemainingByTask[taskId] = savedTimerSeconds
                timerIsRunning = true
            } else {
                savedTimerSeconds = 0
                timerRemainingByTask[taskId] = 0
                finishTimer(preserveCompletionNotification: true)
            }
        }

        if wasBlockedByOldRingingState {
            timerIsRunning = false
            timerEndDate = nil
            savedTimerSeconds = timerTargetSeconds
            timerRemainingByTask[taskId] = savedTimerSeconds
            cancelTimerNotification()
        }

        updateTicker()
        persistTimerState()
        if UserDefaults.standard.bool(forKey: TimerNotificationConstants.stopRequestStorageKey) {
            stopTimerAlarm()
        }
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
            if let fileName = selectedAlert.soundFileName {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(fileName))
            }
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

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: eventStorageKey)
    }

    private func persistCategories() {
        UserDefaults.standard.set(categories, forKey: categoryStorageKey)
    }

    private func restoreFocusSessions() {
        if let data = UserDefaults.standard.data(forKey: focusSessionStorageKey),
           let sessions = try? JSONDecoder().decode([FocusSession].self, from: data) {
            focusSessions = sessions
            persistFocusSessions()
        }
    }

    private func recordFocusSession(duration: Int, category: String?) {
        focusSessions.append(FocusSession(
            completedAt: Date(),
            durationSeconds: duration,
            category: normalizedTaskCategory(category)
        ))
        persistFocusSessions()
    }

    func updateFocusSession(id: String, durationSeconds: Int, category: String?) {
        guard let index = focusSessions.firstIndex(where: { $0.id == id }) else { return }
        var updatedSessions = focusSessions
        updatedSessions[index].durationSeconds = max(1, durationSeconds)
        updatedSessions[index].category = normalizedTaskCategory(category)
        focusSessions = updatedSessions
        persistFocusSessions()
    }

    private func persistFocusSessions() {
        if let data = try? JSONEncoder().encode(focusSessions) {
            UserDefaults.standard.set(data, forKey: focusSessionStorageKey)
        }
    }

    var totalFocusSeconds: Int {
        focusSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    func focusSeconds(in interval: DateInterval) -> Int {
        focusSessions
            .filter { interval.contains($0.completedAt) }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    func focusSessionCount(in interval: DateInterval) -> Int {
        focusSessions.lazy.filter { interval.contains($0.completedAt) }.count
    }

    func focusSecondsByCategory(in interval: DateInterval) -> [String: Int] {
        focusSessions
            .filter { interval.contains($0.completedAt) }
            .reduce(into: [:]) { result, session in
                let trimmedCategory = session.category?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = trimmedCategory.flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
                result[name, default: 0] += session.durationSeconds
            }
    }

    private func normalizedTaskCategory(_ category: String?) -> String? {
        guard let category = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !category.isEmpty,
              let storedCategory = categories.first(where: {
                  $0.localizedCaseInsensitiveCompare(category) == .orderedSame
              }) else { return nil }
        return storedCategory
    }
}
