import Foundation
import UIKit
import UserNotifications

struct FlowTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var estimate: Int
    var done: Bool

    init(
        id: String,
        title: String,
        estimate: Int = 25,
        done: Bool = false
    ) {
        self.id = id
        self.title = title
        self.estimate = estimate
        self.done = done
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, estimate, done
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        estimate = min(1_439, max(1, try container.decodeIfPresent(Int.self, forKey: .estimate) ?? 25))
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
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

enum TimerEndAlert: String, CaseIterable, Identifiable, Codable {
    case defaultSound = "Default"
    case chime = "Chime"
    case pulse = "Pulse"
    case jetLock = "Jet Lock"
    case silent = "Silent"

    var id: String { rawValue }

    var displayName: String {
        self == .defaultSound ? "Classic" : rawValue
    }

    var description: String {
        switch self {
        case .defaultSound: return "Alternating alarm"
        case .chime: return "Bright three-note chime"
        case .pulse: return "Electronic double pulse"
        case .jetLock: return "Original fighter-jet radar warning"
        case .silent: return "Notification without sound"
        }
    }

    var soundFileName: String? {
        switch self {
        case .defaultSound: return "flowtime-alarm.wav"
        case .chime: return "flowtime-chime.wav"
        case .pulse: return "flowtime-pulse.wav"
        case .jetLock: return "flowtime-jet-lock.wav"
        case .silent: return nil
        }
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

private struct PersistedFocusSession: Codable {
    let completedAt: Date
    let durationSeconds: Int
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
    @Published var weeklyFocusSeconds = 0
    @Published var sessionCount = 0

    private var ticker: Timer?
    private var savedTimerSeconds = 0
    private var timerTargetSeconds = 0
    private var timerIsRunning = false
    private var timerEndDate: Date?
    private var focusLabel = ""
    private var focusSessions: [PersistedFocusSession] = []
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

        restoreFocusSessions()
        restoreTimerState()
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
        if updatedTask.done { removeTimer(for: updatedTask.id) }
        persistTasks()
    }

    func addTask(title: String, estimate: Int) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let task = FlowTask(
            id: UUID().uuidString,
            title: cleanTitle,
            estimate: min(1_439, max(1, estimate))
        )
        tasks.insert(task, at: 0)
        persistTasks()
    }

    func updateTask(_ task: FlowTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousTask = tasks[index]
        var cleanTask = task
        cleanTask.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanTask.estimate = min(1_439, max(1, task.estimate))
        guard !cleanTask.title.isEmpty else { return }
        tasks[index] = cleanTask
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
        } else if timerIsRinging, alert == .silent {
            cancelTimerNotification()
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
        timerIsRunning = false
        timerEndDate = nil
        timerIsRinging = false
        if preserveCompletionNotification {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            cancelTimerNotification()
        }
        if duration > 0 { recordFocusSession(duration: duration) }
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
