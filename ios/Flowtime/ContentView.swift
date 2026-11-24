import SwiftUI
import Charts
import UIKit
import UserNotifications
import AVFoundation

private enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @AppStorage("flowtime.appearance") private var appearance = AppTheme.dark.rawValue

    private var appTheme: AppTheme {
        AppTheme(rawValue: appearance) ?? .dark
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(0)
            TaskListView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                .tag(1)
            FocusView()
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(2)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar") }
                .tag(3)
        }
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Color(.systemBackground).ignoresSafeArea())
        .preferredColorScheme(appTheme.colorScheme)
    }
}

private enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case year = "Year"
    case month = "Month"
    case week = "Week"
    case day = "Day"
    var id: String { rawValue }
}

private func flowCategoryColor(_ category: String) -> Color {
    switch category {
    case "Work": return .blue
    case "Personal": return .green
    case "Focus time": return .purple
    default:
        let palette: [Color] = [.orange, .pink, .teal, .indigo, .mint, .cyan]
        let value = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[value % palette.count]
    }
}

private struct TodayView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var showingNewEvent = false
    @State private var showingCategories = false
    @State private var selectedEvent: FlowEvent?
    @State private var displayMode: CalendarDisplayMode = .day

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: store.selectedDate)
        let start = interval?.start ?? calendar.startOfDay(for: store.selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Button {
                            changePeriod(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 36, height: 36)
                        }
                        Spacer()
                        Text(periodTitle)
                            .font(.headline)
                        Spacer()
                        Button {
                            changePeriod(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 36, height: 36)
                        }
                    }

                    Picker("Calendar view", selection: $displayMode) {
                        ForEach(CalendarDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch displayMode {
                    case .year:
                        YearCalendarView(date: store.selectedDate, events: store.events) { month in
                            store.selectedDate = month
                            displayMode = .month
                        }
                    case .month:
                        MonthCalendarView(date: store.selectedDate, events: store.events) { day in
                            store.selectedDate = day
                            displayMode = .day
                        }
                    case .week:
                        WeekCalendarView(
                            dates: weekDates,
                            events: store.events,
                            onSelectDay: { store.selectedDate = $0 },
                            onSelectEvent: { selectedEvent = $0 }
                        )
                    case .day:
                        HStack(spacing: 4) {
                            ForEach(weekDates, id: \.self) { date in
                                dayButton(date)
                            }
                        }
                        DayCalendarView(
                            date: store.selectedDate,
                            events: store.events(on: store.selectedDate),
                            onSelect: { selectedEvent = $0 }
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New event", systemImage: "calendar.badge.plus") { showingNewEvent = true }
                        Button("Manage categories", systemImage: "tag") { showingCategories = true }
                        Divider()
                        Button("Go to today", systemImage: "calendar") { store.selectedDate = Date() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
                }
            }
            .sheet(isPresented: $showingNewEvent) { NewEventSheet(date: store.selectedDate) }
            .sheet(isPresented: $showingCategories) { CategoryManagerSheet() }
            .sheet(item: $selectedEvent) { event in EventDetailSheet(event: event) }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { store.selectedDate = date }
        } label: {
            VStack(spacing: 7) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.bold())
                    .frame(width: 38, height: 38)
                    .background(isSelected(date) ? Color.accentColor : .clear)
                    .foregroundStyle(isSelected(date) ? .white : .primary)
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: store.selectedDate)
    }

    private var periodTitle: String {
        switch displayMode {
        case .year:
            return store.selectedDate.formatted(.dateTime.year())
        case .month:
            return store.selectedDate.formatted(.dateTime.month(.wide).year())
        case .week:
            guard let first = weekDates.first, let last = weekDates.last else { return "Week" }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .day:
            return store.selectedDate.formatted(.dateTime.month(.wide).day().year())
        }
    }

    private func changePeriod(by value: Int) {
        let component: Calendar.Component
        switch displayMode {
        case .year: component = .year
        case .month: component = .month
        case .week: component = .weekOfYear
        case .day: component = .day
        }
        guard let date = Calendar.current.date(byAdding: component, value: value, to: store.selectedDate) else { return }
        withAnimation(.easeOut(duration: 0.18)) { store.selectedDate = date }
    }
}

private struct WeekCalendarView: View {
    let dates: [Date]
    let events: [FlowEvent]
    let onSelectDay: (Date) -> Void
    let onSelectEvent: (FlowEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let dayEvents = events.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: date) }
                    .sorted { $0.startsAt < $1.startsAt }
                VStack(alignment: .leading, spacing: 9) {
                    Button { onSelectDay(date) } label: {
                        HStack {
                            Text(date.formatted(.dateTime.weekday(.wide)))
                                .font(.headline)
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(dayEvents.count)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if dayEvents.isEmpty {
                        Text("No events")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(dayEvents) { event in
                            Button { onSelectEvent(event) } label: {
                                HStack(spacing: 10) {
                                    Text(event.isAllDay ? "All day" : event.startsAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 68, alignment: .leading)
                                    EventBlock(event: event)
                                        .frame(height: 50)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 14)
                if date != dates.last { Divider() }
            }
        }
        .padding(.horizontal, 18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct MonthCalendarView: View {
    let date: Date
    let events: [FlowEvent]
    let onSelectDay: (Date) -> Void

    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let actualDays = range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + actualDays
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { onSelectDay(day) } label: {
                            VStack(spacing: 5) {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                                    .frame(width: 32, height: 32)
                                    .background(Calendar.current.isDateInToday(day) ? Color.accentColor : .clear)
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                                    .clipShape(Circle())
                                HStack(spacing: 2) {
                                    ForEach(Array(eventsOn(day).prefix(3))) { event in
                                        Circle().fill(eventColor(event)).frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func eventsOn(_ day: Date) -> [FlowEvent] {
        events.filter { Calendar.current.isDate($0.startsAt, inSameDayAs: day) }
    }

    private func eventColor(_ event: FlowEvent) -> Color {
        flowCategoryColor(event.category)
    }
}

private struct YearCalendarView: View {
    let date: Date
    let events: [FlowEvent]
    let onSelectMonth: (Date) -> Void

    private var months: [Date] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(months, id: \.self) { month in
                Button { onSelectMonth(month) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(month.formatted(.dateTime.month(.wide)))
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        let count = eventCount(in: month)
                        Text(count == 0 ? "No events" : "\(count) event\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { index in
                                Capsule()
                                    .fill(index < min(count, 7) ? Color.accentColor : Color.secondary.opacity(0.14))
                                    .frame(height: 5)
                            }
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func eventCount(in month: Date) -> Int {
        events.filter {
            Calendar.current.isDate($0.startsAt, equalTo: month, toGranularity: .month)
        }.count
    }
}

private struct DayCalendarView: View {
    let date: Date
    let events: [FlowEvent]
    let onSelect: (FlowEvent) -> Void

    private let startHour = 7
    private let endHour = 21
    private let hourHeight: CGFloat = 68
    private let timeColumnWidth: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.title3.bold())
                    Text(events.isEmpty ? "No events scheduled" : "\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "calendar.day.timeline.left")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            let allDayEvents = events.filter(\.isAllDay)
            if !allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ALL-DAY")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    ForEach(allDayEvents) { event in
                        Button { onSelect(event) } label: {
                            EventBlock(event: event)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 8) {
                            Text(hourLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: timeColumnWidth, alignment: .trailing)
                                .offset(y: -7)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.17))
                                .frame(height: 1)
                        }
                        .offset(y: CGFloat(hour - startHour) * hourHeight)
                    }

                    ForEach(events.filter { !$0.isAllDay }) { event in
                        if eventHour(event) >= startHour && eventHour(event) < endHour {
                            Button { onSelect(event) } label: {
                                EventBlock(event: event)
                            }
                            .buttonStyle(.plain)
                            .frame(
                                width: max(120, proxy.size.width - timeColumnWidth - 18),
                                height: max(42, CGFloat(event.durationMinutes) / 60 * hourHeight),
                                alignment: .topLeading
                            )
                            .offset(x: timeColumnWidth + 10, y: eventOffset(event))
                        }
                    }

                    if Calendar.current.isDateInToday(date) {
                        let now = Date()
                        let hour = Calendar.current.component(.hour, from: now)
                        if hour >= startHour && hour < endHour {
                            HStack(spacing: 0) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Rectangle().fill(Color.red).frame(height: 1)
                            }
                            .offset(x: timeColumnWidth + 5, y: eventOffset(now))
                        }
                    }
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight)
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func eventHour(_ event: FlowEvent) -> Int {
        Calendar.current.component(.hour, from: event.startsAt)
    }

    private func eventOffset(_ event: FlowEvent) -> CGFloat {
        eventOffset(event.startsAt)
    }

    private func eventOffset(_ time: Date) -> CGFloat {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? startHour
        let minute = components.minute ?? 0
        return (CGFloat(hour - startHour) + CGFloat(minute) / 60) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour == 12 { return "12 PM" }
        return hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
    }
}

private struct EventBlock: View {
    let event: FlowEvent

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text(event.startsAt.formatted(date: .omitted, time: .shortened))
                    }
                }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        flowCategoryColor(event.category)
    }
}

private struct NewEventSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var title = ""
    @State private var startTime: Date
    @State private var duration = 60
    @State private var category = "Work"
    @State private var isAllDay = false
    @FocusState private var titleFocused: Bool

    init(date: Date) {
        self.date = date
        let defaultTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        _startTime = State(initialValue: defaultTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Event title", text: $title)
                        .focused($titleFocused)
                    DatePicker("Date", selection: Binding(
                        get: { date },
                        set: { _ in }
                    ), displayedComponents: .date)
                    .disabled(true)
                    Toggle("All-day", isOn: $isAllDay)
                    if !isAllDay {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                        Stepper("Duration: \(duration) minutes", value: $duration, in: 15...480, step: 15)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(store.categories, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addEvent(
                            title: title,
                            date: date,
                            startTime: startTime,
                            durationMinutes: duration,
                            category: category,
                            isAllDay: isAllDay
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if !store.categories.contains(category) { category = store.categories.first ?? "Uncategorized" }
                titleFocused = true
            }
        }
    }
}

private struct EventDetailSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    let event: FlowEvent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if event.isAllDay {
                        Label(event.startsAt.formatted(date: .complete, time: .omitted), systemImage: "calendar")
                        Label("All day", systemImage: "sun.max")
                    } else {
                        Label(event.startsAt.formatted(date: .complete, time: .shortened), systemImage: "clock")
                        Label("\(event.durationMinutes) minutes", systemImage: "hourglass")
                    }
                    Label(event.category, systemImage: "tag")
                }
                Section {
                    Button("Delete event", systemImage: "trash", role: .destructive) {
                        store.delete(event)
                        dismiss()
                    }
                }
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct CategoryManagerSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    @State private var newCategory = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Add category") {
                    HStack {
                        TextField("Category name", text: $newCategory)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(addCategory)
                        Button("Add", action: addCategory)
                            .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    ForEach(store.categories, id: \.self) { category in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(flowCategoryColor(category))
                                .frame(width: 10, height: 10)
                            Text(category)
                        }
                    }
                    .onDelete { offsets in
                        let names = offsets.map { store.categories[$0] }
                        for name in names { store.deleteCategory(name) }
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Swipe left to delete. Existing events will be moved to another category.")
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func addCategory() {
        store.addCategory(newCategory)
        newCategory = ""
        nameFocused = true
    }
}

private struct TaskCell: View {
    let task: FlowTask
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(task.done ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)

                Label(formattedTaskEstimate(task.estimate), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit task")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct TaskEditorTarget: Identifiable {
    let id = UUID()
    let task: FlowTask?
}

private struct TaskListView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var editorTarget: TaskEditorTarget?
    @State private var showingCompleted = false
    @State private var feedbackTrigger = 0

    private var openTasks: [FlowTask] {
        store.tasks.filter { !$0.done }
    }

    private var completedTasks: [FlowTask] {
        store.tasks.filter(\.done)
    }

    var body: some View {
        NavigationStack {
            Group {
                if openTasks.isEmpty && !(showingCompleted && !completedTasks.isEmpty) {
                    ContentUnavailableView(
                        completedTasks.isEmpty ? "No Tasks" : "All Done",
                        systemImage: completedTasks.isEmpty ? "checklist" : "checkmark.circle",
                        description: Text(completedTasks.isEmpty
                            ? "Add something you plan to do and estimate how long it will take."
                            : "You completed everything on your list.")
                    )
                } else {
                    List {
                        ForEach(openTasks) { task in
                            taskRow(task)
                        }

                        if showingCompleted, !completedTasks.isEmpty {
                            Section("Completed") {
                                ForEach(completedTasks) { task in
                                    taskRow(task)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !completedTasks.isEmpty {
                        Menu {
                            Button(showingCompleted ? "Hide Completed" : "Show Completed",
                                   systemImage: showingCompleted ? "eye.slash" : "eye") {
                                withAnimation { showingCompleted.toggle() }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Task options")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button {
                        editorTarget = TaskEditorTarget(task: nil)
                    } label: {
                        Label("New Task", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                    .accessibilityHint("Add a task and estimated time")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .sheet(item: $editorTarget) { target in
                TaskEditorSheet(task: target.task)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sensoryFeedback(.selection, trigger: feedbackTrigger)
        }
    }

    private func taskRow(_ task: FlowTask) -> some View {
        TaskCell(
            task: task,
            onToggle: {
                withAnimation {
                    store.toggle(task)
                    feedbackTrigger += 1
                }
            },
            onEdit: { editorTarget = TaskEditorTarget(task: task) }
        )
        .listRowBackground(Color(.systemBackground))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation { store.delete(task) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                withAnimation {
                    store.toggle(task)
                    feedbackTrigger += 1
                }
            } label: {
                Label(task.done ? "Reopen" : "Complete",
                      systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(Color.accentColor)
        }
    }
}

private struct TaskEditorSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    let task: FlowTask?
    @State private var title: String
    @State private var estimateMinutes: Int
    @FocusState private var titleFocused: Bool
    private let presets = [5, 15, 20, 25, 30, 60, 120]

    init(task: FlowTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        let initialEstimate = task?.estimate ?? 25
        _estimateMinutes = State(initialValue: min(1_439, max(1, initialEstimate)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you plan to do?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.title3)
                        .focused($titleFocused)
                }

                Section("Estimated time") {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: estimateHours) {
                            ForEach(0...23, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text("hr")
                            .foregroundStyle(.secondary)

                        Picker("Minutes", selection: estimateMinutePart) {
                            ForEach(0...59, id: \.self) { value in
                                Text(String(format: "%02d", value)).tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 150)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(presets, id: \.self) { minutes in
                            Button {
                                estimateMinutes = minutes
                            } label: {
                                Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(estimateMinutes == minutes ? Color.accentColor : Color.secondary.opacity(0.25))
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: estimateMinutes)
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private var estimateHours: Binding<Int> {
        Binding(
            get: { estimateMinutes / 60 },
            set: { hours in
                estimateMinutes = min(1_439, max(1, hours * 60 + estimateMinutes % 60))
            }
        )
    }

    private var estimateMinutePart: Binding<Int> {
        Binding(
            get: { estimateMinutes % 60 },
            set: { minutes in
                estimateMinutes = min(1_439, max(1, (estimateMinutes / 60) * 60 + minutes))
            }
        )
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if var updated = task {
            updated.title = title
            updated.estimate = estimateMinutes
            store.updateTask(updated)
        } else {
            store.addTask(title: title, estimate: estimateMinutes)
        }
        dismiss()
    }
}

private func formattedTaskEstimate(_ minutes: Int) -> String {
    let safeMinutes = max(0, minutes)
    let hours = safeMinutes / 60
    let remainingMinutes = safeMinutes % 60
    if hours == 0 { return "\(remainingMinutes) min" }
    if remainingMinutes == 0 { return hours == 1 ? "1 hr" : "\(hours) hr" }
    return "\(hours) hr \(remainingMinutes) min"
}

private struct FocusView: View {
    var body: some View {
        NavigationStack {
            ClockTimerView()
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Timers")
                .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        }
    }
}

private struct ClockTimerView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var feedbackTrigger = 0

    private var availableTasks: [FlowTask] {
        store.tasks.filter { !$0.done }
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableTasks.isEmpty {
                ContentUnavailableView(
                    "No Task Timers",
                    systemImage: "timer",
                    description: Text("Add a task in Tasks and it will appear here with its estimated time.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(availableTasks) { task in
                            TaskTimerCard(
                                task: task,
                                remainingSeconds: store.timerRemainingSeconds(for: task),
                                isRunning: store.timerIsRunning(for: task),
                                isSelected: store.selectedFocusTaskId == task.id,
                                hasStarted: store.timerHasStarted(for: task),
                                onToggle: {
                                    store.toggleTimer(for: task)
                                    feedbackTrigger += 1
                                },
                                onReset: {
                                    store.resetTimer(for: task)
                                    feedbackTrigger += 1
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
    }
}

private struct TaskTimerCard: View {
    let task: FlowTask
    let remainingSeconds: Int
    let isRunning: Bool
    let isSelected: Bool
    let hasStarted: Bool
    let onToggle: () -> Void
    let onReset: () -> Void

    private var targetSeconds: Int {
        task.estimate * 60
    }

    private var elapsedProgress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(1, max(0, Double(targetSeconds - remainingSeconds) / Double(targetSeconds)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Text(formattedTaskEstimate(task.estimate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(timerClockTime(remainingSeconds))
                    .font(.system(size: remainingSeconds >= 3_600 ? 36 : 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if hasStarted {
                    TimerCardButton(title: "Reset", color: .gray, action: onReset)
                }

                TimerCardButton(
                    title: isRunning ? "Stop" : (hasStarted ? "Resume" : "Start"),
                    color: isRunning ? .orange : .green,
                    action: onToggle
                )
            }

            if hasStarted {
                ProgressView(value: elapsedProgress)
                    .tint(isRunning ? .orange : Color.accentColor)
                    .animation(.linear(duration: 0.25), value: elapsedProgress)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? (isRunning ? Color.orange : Color.accentColor) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TimerCardButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(minWidth: 64, minHeight: 44)
                .background(color.opacity(0.16))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private func timerClockTime(_ duration: Int) -> String {
    let safeDuration = max(0, duration)
    if safeDuration >= 3_600 {
        return String(
            format: "%d:%02d:%02d",
            safeDuration / 3_600,
            (safeDuration % 3_600) / 60,
            safeDuration % 60
        )
    }
    return String(format: "%02d:%02d", safeDuration / 60, safeDuration % 60)
}

@MainActor
private final class TimerSoundPreviewPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var stopWorkItem: DispatchWorkItem?

    func play(_ alert: TimerEndAlert) {
        stop()
        guard let url = TimerAlarmSound.fileURL(for: alert) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()

            let workItem = DispatchWorkItem { [weak self] in self?.stop() }
            stopWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        } catch {
            player = nil
        }
    }

    func stop() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        player?.stop()
        player = nil
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("flowtime.appearance") private var appearance = AppTheme.dark.rawValue
    @StateObject private var previewPlayer = TimerSoundPreviewPlayer()
    @State private var notificationStatus: UNAuthorizationStatus?

    private var currentTheme: AppTheme {
        AppTheme(rawValue: appearance) ?? .dark
    }

    private var themeSelection: Binding<AppTheme> {
        Binding(
            get: { currentTheme },
            set: { appearance = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: themeSelection) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(TimerEndAlert.allCases) { alert in
                        HStack(spacing: 12) {
                            Button {
                                store.setTimerEndAlert(alert)
                                if alert == .silent {
                                    previewPlayer.stop()
                                } else {
                                    previewPlayer.play(alert)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: soundIcon(for: alert))
                                        .foregroundStyle(alert == .jetLock ? Color.orange : Color.accentColor)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(alert.displayName)
                                            .foregroundStyle(.primary)
                                        Text(alert.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if store.timerEndAlert == alert {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if alert.soundFileName != nil {
                                Button {
                                    previewPlayer.play(alert)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview \(alert.displayName)")
                            }
                        }
                    }
                } header: {
                    Text("When Timer Ends")
                } footer: {
                    Text("Jet Lock is an original synthesized fighter-jet radar warning tone.")
                }

                Section {
                    Button("Open Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                } footer: {
                    if notificationStatus == .denied {
                        Text("Notifications are disabled for Flowtime. Enable them to receive timer alerts while the app is closed or your iPhone is locked.")
                    } else {
                        Text("For a banner that stays until tapped, choose Banners and set Banner Style to Persistent.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .onDisappear { previewPlayer.stop() }
        }
        .preferredColorScheme(currentTheme.colorScheme)
    }

    private func soundIcon(for alert: TimerEndAlert) -> String {
        switch alert {
        case .defaultSound: return "bell.fill"
        case .chime: return "music.note"
        case .pulse: return "waveform"
        case .jetLock: return "airplane"
        case .silent: return "speaker.slash.fill"
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private enum InsightRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }
}

private struct InsightMetric: Identifiable {
    let id: String
    let label: String
    let value: Double
}

private struct CategoryMetric: Identifiable {
    let id: String
    let name: String
    let hours: Double
}

private struct InsightsView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var range: InsightRange = .week
    @State private var showingSettings = false
    private let weeklyValues = [4.2, 5.5, 3.1, 6.4, 4.8, 2.2, 1.4]
    private let monthlyValues = [3.5, 4.7, 5.9, 4.1, 6.2, 3.8, 5.1]
    private let trendData = [
        InsightMetric(id: "w1", label: "W1", value: 14.2),
        InsightMetric(id: "w2", label: "W2", value: 17.8),
        InsightMetric(id: "w3", label: "W3", value: 16.1),
        InsightMetric(id: "w4", label: "W4", value: 21.4),
        InsightMetric(id: "w5", label: "W5", value: 18.4)
    ]
    private let categoryData = [
        CategoryMetric(id: "work", name: "Work", hours: 10.4),
        CategoryMetric(id: "focus", name: "Focus time", hours: 5.8),
        CategoryMetric(id: "personal", name: "Personal", hours: 2.2)
    ]
    private let hourlyData = [
        InsightMetric(id: "8", label: "8 AM", value: 42),
        InsightMetric(id: "10", label: "10 AM", value: 81),
        InsightMetric(id: "12", label: "12 PM", value: 54),
        InsightMetric(id: "14", label: "2 PM", value: 92),
        InsightMetric(id: "16", label: "4 PM", value: 68),
        InsightMetric(id: "18", label: "6 PM", value: 31)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Insight range", selection: $range) {
                        ForEach(InsightRange.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)

                    Text(range == .week ? formattedDuration(store.weeklyFocusSeconds) : "72h 10m")
                        .font(.system(size: 38, weight: .bold))
                    Text(range == .week ? "Focused this week" : "Focused this month")
                        .foregroundStyle(.secondary)

                    InsightCard(title: "Focus by day", subtitle: "Hours of focused work") {
                        Chart(dailyData) { item in
                            BarMark(
                                x: .value("Day", item.label),
                                y: .value("Hours", item.value)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(5)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .animation(.easeInOut(duration: 0.25), value: range)
                    }

                    HStack(spacing: 12) {
                        StatTile(value: "\(store.tasks.filter(\.done).count)", label: "Tasks completed")
                        StatTile(value: "\(store.sessionCount)", label: "Focus sessions")
                    }

                    InsightCard(title: "Focus trend", subtitle: "Last five weeks") {
                        Chart(trendData) { item in
                            AreaMark(
                                x: .value("Week", item.label),
                                y: .value("Hours", item.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("Week", item.label),
                                y: .value("Hours", item.value)
                            )
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            PointMark(
                                x: .value("Week", item.label),
                                y: .value("Hours", item.value)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .chartYScale(domain: 0...24)
                    }

                    InsightCard(title: "Time by category", subtitle: "Where your focus went") {
                        HStack(spacing: 20) {
                            Chart(categoryData) { item in
                                SectorMark(
                                    angle: .value("Hours", item.hours),
                                    innerRadius: .ratio(0.62),
                                    angularInset: 2
                                )
                                .foregroundStyle(by: .value("Category", item.name))
                                .cornerRadius(4)
                            }
                            .chartForegroundStyleScale([
                                "Work": Color.blue,
                                "Focus time": Color.purple,
                                "Personal": Color.green
                            ])
                            .chartLegend(.hidden)
                            .frame(width: 145)

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(categoryData) { item in
                                    HStack {
                                        Circle().fill(categoryColor(item.name)).frame(width: 8, height: 8)
                                        Text(item.name).font(.caption)
                                        Spacer()
                                        Text("\(item.hours, specifier: "%.1f")h")
                                            .font(.caption.bold())
                                    }
                                }
                            }
                        }
                    }

                    InsightCard(title: "Productive hours", subtitle: "Focus score throughout the day") {
                        Chart(hourlyData) { item in
                            BarMark(
                                x: .value("Time", item.label),
                                y: .value("Focus score", item.value)
                            )
                            .foregroundStyle(item.value >= 80 ? Color.green.gradient : Color.accentColor.gradient)
                            .cornerRadius(4)
                        }
                        .chartYScale(domain: 0...100)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var values: [Double] { range == .week ? weeklyValues : monthlyValues }
    private var dailyData: [InsightMetric] {
        zip(["M", "T", "W", "T", "F", "S", "S"], values).enumerated().map { index, pair in
            InsightMetric(id: "day-\(index)", label: pair.0, value: pair.1)
        }
    }

    private func categoryColor(_ name: String) -> Color {
        name == "Personal" ? .green : name == "Focus time" ? .purple : .blue
    }

    private func formattedDuration(_ seconds: Int) -> String {
        "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }
}

private struct InsightCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
                .frame(height: 210)
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
