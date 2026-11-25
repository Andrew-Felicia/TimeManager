import SwiftUI
import Charts
import UIKit
import UserNotifications
import AVFoundation
import UniformTypeIdentifiers

private let appEnglishLocale = Locale(identifier: "en_US")

private func englishDateString(_ date: Date, _ format: Date.FormatStyle) -> String {
    date.formatted(format.locale(appEnglishLocale))
}

private func englishDateString(
    _ date: Date,
    dateStyle: DateFormatter.Style,
    timeStyle: DateFormatter.Style
) -> String {
    let formatter = DateFormatter()
    formatter.locale = appEnglishLocale
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: date)
}

private struct FlowtimeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

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
        .environment(\.locale, appEnglishLocale)
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
    case "Other": return .secondary
    default:
        let palette: [Color] = [.orange, .pink, .teal, .indigo, .mint, .cyan]
        let value = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[value % palette.count]
    }
}

private func taskPriorityColor(_ priority: TaskPriority) -> Color {
    switch priority {
    case .low: return .blue
    case .medium: return .orange
    case .high: return .red
    }
}

private struct EventDateIndicator: View {
    let events: [FlowEvent]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(events.prefix(3))) { event in
                Capsule()
                    .fill(flowCategoryColor(event.category))
                    .frame(width: 8, height: 3)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

private struct TaskPriorityLabel: View {
    let priority: TaskPriority

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(taskPriorityColor(priority))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(priority.rawValue)
        }
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
                Text(englishDateString(date, .dateTime.weekday(.narrow)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(englishDateString(date, .dateTime.day()))
                    .font(.subheadline.bold())
                    .frame(width: 38, height: 38)
                    .background(isSelected(date) ? Color.accentColor : .clear)
                    .foregroundStyle(isSelected(date) ? .white : .primary)
                    .clipShape(Circle())
                EventDateIndicator(events: store.events(on: date))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(englishDateString(date, dateStyle: .full, timeStyle: .none))
        .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: store.selectedDate)
    }

    private var periodTitle: String {
        switch displayMode {
        case .year:
            return englishDateString(store.selectedDate, .dateTime.year())
        case .month:
            return englishDateString(store.selectedDate, .dateTime.month(.wide).year())
        case .week:
            guard let first = weekDates.first, let last = weekDates.last else { return "Week" }
            return "\(englishDateString(first, .dateTime.month(.abbreviated).day())) – \(englishDateString(last, .dateTime.month(.abbreviated).day()))"
        case .day:
            return englishDateString(store.selectedDate, .dateTime.month(.wide).day().year())
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
                let dayEvents = events.filter { $0.occurs(on: date) }
                    .sorted { $0.startsAt < $1.startsAt }
                VStack(alignment: .leading, spacing: 9) {
                    Button { onSelectDay(date) } label: {
                        HStack {
                            Text(englishDateString(date, .dateTime.weekday(.wide)))
                                .font(.headline)
                            Text(englishDateString(date, .dateTime.month(.abbreviated).day()))
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
                                    Text(event.isAllDay
                                        ? "All day"
                                        : englishDateString(event.startsAt, dateStyle: .none, timeStyle: .short))
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
                                Text(englishDateString(day, .dateTime.day()))
                                    .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                                    .frame(width: 32, height: 32)
                                    .background(Calendar.current.isDateInToday(day) ? Color.accentColor : .clear)
                                    .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                                    .clipShape(Circle())
                                EventDateIndicator(events: eventsOn(day))
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
        let formatter = DateFormatter()
        formatter.locale = appEnglishLocale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func eventsOn(_ day: Date) -> [FlowEvent] {
        events.filter { $0.occurs(on: day) }
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
                            Text(englishDateString(month, .dateTime.month(.wide)))
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
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: month) else { return 0 }
        return events.filter { event in
            event.startsAt < monthInterval.end && event.endsAt > monthInterval.start
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
                    Text(englishDateString(date, .dateTime.weekday(.wide).month(.abbreviated).day()))
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
                Text(event.isAllDay ? event.category : event.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text("All day")
                    } else {
                        Text("\(englishDateString(event.startsAt, dateStyle: .none, timeStyle: .short)) – \(englishDateString(event.endsAt, dateStyle: .none, timeStyle: .short))")
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
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var category = "Work"

    init(date: Date) {
        let selectedDay = Calendar.current.startOfDay(for: date)
        _startDate = State(initialValue: selectedDay)
        _endDate = State(initialValue: selectedDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends date", selection: $endDate, in: startDate..., displayedComponents: .date)
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
                            startDate: startDate,
                            endDate: endDate,
                            category: category
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !store.categories.contains(category) { category = store.categories.first ?? "Uncategorized" }
            }
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart {
                    endDate = newStart
                }
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
                        LabeledContent("Starts date") {
                            Text(englishDateString(event.startsAt, dateStyle: .medium, timeStyle: .none))
                        }
                        LabeledContent("Ends date") {
                            Text(englishDateString(event.inclusiveEndDate, dateStyle: .medium, timeStyle: .none))
                        }
                    } else {
                        Label(englishDateString(event.startsAt, dateStyle: .full, timeStyle: .none), systemImage: "calendar")
                        Label(
                            "\(englishDateString(event.startsAt, dateStyle: .none, timeStyle: .short)) – \(englishDateString(event.endsAt, dateStyle: .none, timeStyle: .short))",
                            systemImage: "clock"
                        )
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
            .navigationTitle(event.isAllDay ? event.category : event.title)
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
                    Text("Swipe left to delete. Existing events move to another category, and tasks move to Other.")
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

                HStack(spacing: 12) {
                    Label(formattedTaskEstimate(task.estimate), systemImage: "clock")
                    TaskPriorityLabel(priority: task.priority)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(formattedTaskSchedule(task.scheduledAt), systemImage: "calendar")
                    Label(task.category ?? "Other", systemImage: "tag")
                        .foregroundStyle(flowCategoryColor(task.category ?? "Other"))
                }
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
    @State private var showingCategories = false
    @State private var feedbackTrigger = 0

    private var openTasks: [FlowTask] {
        store.activeTasks
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
                    Menu {
                        Button("Manage Categories", systemImage: "tag") {
                            showingCategories = true
                        }
                        if !completedTasks.isEmpty {
                            Button(showingCompleted ? "Hide Completed" : "Show Completed",
                                   systemImage: showingCompleted ? "eye.slash" : "eye") {
                                withAnimation { showingCompleted.toggle() }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Task options")
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
            .sheet(isPresented: $showingCategories) {
                CategoryManagerSheet()
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
    @State private var selectedCategory: String?
    @State private var priority: TaskPriority
    @State private var scheduledDate: Date
    @State private var showingCategories = false
    @FocusState private var titleFocused: Bool
    private let presets = [5, 15, 20, 25, 30, 60, 120]

    init(task: FlowTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        let initialEstimate = task?.estimate ?? 25
        _estimateMinutes = State(initialValue: min(1_439, max(1, initialEstimate)))
        _selectedCategory = State(initialValue: task?.category)
        _priority = State(initialValue: task?.priority ?? .medium)
        _scheduledDate = State(initialValue: task?.scheduledAt ?? Date())
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

                Section("Priority") {
                    TaskPrioritySelector(selection: $priority)
                }

                Section("When") {
                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        displayedComponents: .date
                    )
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

                Section {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Other").tag(Optional<String>.none)
                        ForEach(store.categories, id: \.self) { category in
                            Text(category).tag(Optional(category))
                        }
                    }

                    Button("Manage Categories", systemImage: "tag") {
                        showingCategories = true
                    }
                } header: {
                    Text("Category")
                } footer: {
                    Text("Choose Other to exclude this task from categories. Its focus time will be counted under Other.")
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
            .sheet(isPresented: $showingCategories) {
                CategoryManagerSheet()
            }
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
            updated.category = selectedCategory
            updated.priority = priority
            updated.scheduledAt = scheduledDate
            store.updateTask(updated)
        } else {
            store.addTask(
                title: title,
                estimate: estimateMinutes,
                category: selectedCategory,
                priority: priority,
                scheduledAt: scheduledDate
            )
        }
        dismiss()
    }
}

private struct TaskPrioritySelector: View {
    @Binding var selection: TaskPriority

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TaskPriority.allCases) { priority in
                Button {
                    selection = priority
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(taskPriorityColor(priority))
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                        Text(priority.rawValue)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(selection == priority ? taskPriorityColor(priority) : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selection == priority
                            ? taskPriorityColor(priority).opacity(0.16)
                            : Color.secondary.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                selection == priority ? taskPriorityColor(priority).opacity(0.7) : Color.clear,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == priority ? .isSelected : [])
            }
        }
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

private func formattedTaskSchedule(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = appEnglishLocale
    formatter.doesRelativeDateFormatting = true
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
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
        store.activeTasks
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
        .onAppear { store.synchronizeTaskTimers() }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Label(task.category ?? "Other", systemImage: "tag")
                            .foregroundStyle(flowCategoryColor(task.category ?? "Other"))
                        TaskPriorityLabel(priority: task.priority)
                    }
                    .font(.caption)
                }
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

private enum DataTransferAlert: Identifiable {
    case confirmImport
    case importComplete
    case error(String)

    var id: String {
        switch self {
        case .confirmImport: return "confirm-import"
        case .importComplete: return "import-complete"
        case .error(let message): return "error-\(message)"
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("flowtime.appearance") private var appearance = AppTheme.dark.rawValue
    @StateObject private var previewPlayer = TimerSoundPreviewPlayer()
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var exportDocument: FlowtimeExportDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var dataTransferAlert: DataTransferAlert?

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
                    Button(action: prepareExport) {
                        Label("Export All Data", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export creates one JSON backup. Import restores a Flowtime JSON backup and replaces the current data.")
                }

                Section {
                    ForEach(TimerEndAlert.allCases) { alert in
                        HStack(spacing: 12) {
                            Button {
                                store.setTimerEndAlert(alert)
                                previewPlayer.play(alert)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: soundIcon(for: alert))
                                        .foregroundStyle(soundColor(for: alert))
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
                    Text("Inspired by fighter-jet warning patterns. These are original synthesized alerts, not audio copied from the reference videos.")
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
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                let cocoaError = error as NSError
                if cocoaError.code != NSUserCancelledError {
                    dataTransferAlert = .error(error.localizedDescription)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: receiveImport
        )
        .alert(item: $dataTransferAlert) { alert in
            switch alert {
            case .confirmImport:
                return Alert(
                    title: Text("Replace Current Data?"),
                    message: Text("Importing this backup replaces your current tasks, calendar events, categories, insights, timer progress, and settings."),
                    primaryButton: .destructive(Text("Import"), action: performImport),
                    secondaryButton: .cancel { pendingImportData = nil }
                )
            case .importComplete:
                return Alert(
                    title: Text("Import Complete"),
                    message: Text("Your Flowtime data has been restored. Imported timer progress is paused so you can resume it safely."),
                    dismissButton: .default(Text("OK"))
                )
            case .error(let message):
                return Alert(
                    title: Text("Data Transfer Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = appEnglishLocale
        formatter.dateFormat = "yyyy-MM-dd"
        return "Flowtime-Export-\(formatter.string(from: Date()))"
    }

    private func prepareExport() {
        do {
            exportDocument = FlowtimeExportDocument(data: try store.exportData(appearance: appearance))
            showingExporter = true
        } catch {
            dataTransferAlert = .error(error.localizedDescription)
        }
    }

    private func receiveImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            pendingImportData = try Data(contentsOf: url)
            dataTransferAlert = .confirmImport
        } catch {
            let cocoaError = error as NSError
            if cocoaError.code != NSUserCancelledError {
                dataTransferAlert = .error(error.localizedDescription)
            }
        }
    }

    private func performImport() {
        guard let pendingImportData else { return }
        do {
            appearance = try store.importData(pendingImportData)
            self.pendingImportData = nil
            dataTransferAlert = .importComplete
        } catch {
            self.pendingImportData = nil
            dataTransferAlert = .error("This file is not a valid Flowtime JSON backup. \(error.localizedDescription)")
        }
    }

    private func soundIcon(for alert: TimerEndAlert) -> String {
        switch alert {
        case .defaultSound: return "bell.fill"
        case .tws: return "scope"
        case .masterCaution: return "exclamationmark.triangle.fill"
        case .missileLaunch: return "exclamationmark.shield.fill"
        case .rwr: return "antenna.radiowaves.left.and.right"
        }
    }

    private func soundColor(for alert: TimerEndAlert) -> Color {
        switch alert {
        case .defaultSound: return Color.accentColor
        case .tws, .masterCaution, .missileLaunch, .rwr: return .orange
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
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var currentTitle: String {
        switch self {
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        }
    }
}

private struct InsightMetric: Identifiable {
    let id: Date
    let start: Date
    let seconds: Int
}

private struct CategoryMetric: Identifiable {
    var id: String { name }
    let name: String
    let seconds: Int
}

private struct FocusPeriodSummary: Identifiable {
    let range: InsightRange
    let seconds: Int
    var id: InsightRange { range }
}

private struct InsightsView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var range: InsightRange = .week
    @State private var showingSettings = false
    @State private var showingFocusHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    totalFocusCard

                    periodSummaryCard

                    Picker("Insight range", selection: $range) {
                        ForEach(InsightRange.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)

                    InsightCard(
                        title: range.currentTitle,
                        subtitle: "\(store.focusSessionCount(in: selectedInterval)) completed focus sessions"
                    ) {
                        Text(formattedDetailedDuration(selectedFocusSeconds))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)

                        if selectedFocusSeconds == 0 {
                            insightEmptyState(
                                title: "No Focus Time",
                                message: "Complete a task timer to see activity here."
                            )
                        } else {
                            Chart(activityData) { item in
                                BarMark(
                                    x: .value("Period", item.start),
                                    y: .value("Minutes", Double(item.seconds) / 60)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(4)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: axisMarkCount)) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(activityAxisLabel(for: date))
                                        }
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let minutes = value.as(Double.self) {
                                            Text(axisDuration(Int(minutes * 60)))
                                        }
                                    }
                                }
                            }
                            .frame(height: 190)
                            .animation(.easeInOut(duration: 0.25), value: range)
                        }
                    }

                    InsightCard(
                        title: "Time by Category",
                        subtitle: "\(range.currentTitle) · Tasks without a category count as Other"
                    ) {
                        if categoryData.isEmpty {
                            insightEmptyState(
                                title: "No Category Data",
                                message: "Assign categories in Tasks, then complete a timer."
                            )
                        } else {
                            Chart(categoryData) { item in
                                SectorMark(
                                    angle: .value("Seconds", item.seconds),
                                    innerRadius: .ratio(0.64),
                                    angularInset: 2
                                )
                                .foregroundStyle(flowCategoryColor(item.name))
                                .cornerRadius(4)
                            }
                            .chartLegend(.hidden)
                            .frame(height: 180)
                            .overlay {
                                VStack(spacing: 2) {
                                    Text(formattedCompactDuration(selectedFocusSeconds))
                                        .font(.headline)
                                        .monospacedDigit()
                                    Text("total")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(categoryData.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider() }
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(flowCategoryColor(item.name))
                                            .frame(width: 10, height: 10)
                                        Text(item.name)
                                        Spacer()
                                        Text(formattedDetailedDuration(item.seconds))
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    .padding(.vertical, 10)
                                }
                            }
                        }

                        Button {
                            showingFocusHistory = true
                        } label: {
                            Label("Edit Recorded Focus Time", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.focusSessions.isEmpty)
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
            .sheet(isPresented: $showingFocusHistory) {
                FocusHistoryView()
            }
        }
    }

    private var totalFocusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Total Focus Time", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(formattedDetailedDuration(store.totalFocusSeconds))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text("Across \(store.focusSessions.count) completed focus sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var periodSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Focus Summary")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(Array(periodSummaries.enumerated()), id: \.element.id) { index, summary in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Image(systemName: periodIcon(summary.range))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    Text(summary.range.currentTitle)
                    Spacer()
                    Text(formattedDetailedDuration(summary.seconds))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 11)
            }
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var periodSummaries: [FocusPeriodSummary] {
        InsightRange.allCases.map { item in
            FocusPeriodSummary(range: item, seconds: store.focusSeconds(in: interval(for: item)))
        }
    }

    private var selectedInterval: DateInterval {
        interval(for: range)
    }

    private var selectedFocusSeconds: Int {
        store.focusSeconds(in: selectedInterval)
    }

    private var categoryData: [CategoryMetric] {
        store.focusSecondsByCategory(in: selectedInterval)
            .map { CategoryMetric(name: $0.key, seconds: $0.value) }
            .sorted {
                if $0.seconds == $1.seconds {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.seconds > $1.seconds
            }
    }

    private var activityData: [InsightMetric] {
        let interval = selectedInterval
        let calendar = Calendar.current
        let count: Int
        let component: Calendar.Component

        switch range {
        case .day:
            count = 24
            component = .hour
        case .week:
            count = 7
            component = .day
        case .month:
            count = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
            component = .day
        case .year:
            count = 12
            component = .month
        }

        return (0..<count).compactMap { index in
            guard let start = calendar.date(byAdding: component, value: index, to: interval.start),
                  let calculatedEnd = calendar.date(byAdding: component, value: 1, to: start) else { return nil }
            let bucket = DateInterval(start: start, end: min(calculatedEnd, interval.end))
            return InsightMetric(id: start, start: start, seconds: store.focusSeconds(in: bucket))
        }
    }

    private var axisMarkCount: Int {
        switch range {
        case .day: return 6
        case .week: return 7
        case .month: return 6
        case .year: return 6
        }
    }

    private func interval(for range: InsightRange) -> DateInterval {
        Calendar.current.dateInterval(of: range.component, for: Date())
            ?? DateInterval(start: Calendar.current.startOfDay(for: Date()), duration: 86_400)
    }

    private func periodIcon(_ range: InsightRange) -> String {
        switch range {
        case .day: return "sun.max.fill"
        case .week: return "calendar"
        case .month: return "calendar.circle.fill"
        case .year: return "chart.bar.fill"
        }
    }

    private func activityAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appEnglishLocale
        switch range {
        case .day: formatter.dateFormat = "ha"
        case .week: formatter.dateFormat = "EEE"
        case .month: formatter.dateFormat = "d"
        case .year: formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }

    private func formattedDetailedDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        return String(
            format: "%02d h %02d m %02d s",
            safeSeconds / 3_600,
            (safeSeconds % 3_600) / 60,
            safeSeconds % 60
        )
    }

    private func formattedCompactDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(safeSeconds)s"
    }

    private func axisDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        if safeSeconds >= 3_600 { return "\(safeSeconds / 3_600)h" }
        return "\(safeSeconds / 60)m"
    }

    private func insightEmptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct FocusHistoryView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss

    private var sessions: [FocusSession] {
        store.focusSessions.sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Focus Sessions",
                        systemImage: "timer",
                        description: Text("Completed task timers will appear here for correction.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(sessions) { session in
                                NavigationLink {
                                    FocusSessionEditorView(session: session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Label(
                                                focusCategoryName(session.category),
                                                systemImage: "tag.fill"
                                            )
                                            .foregroundStyle(flowCategoryColor(focusCategoryName(session.category)))

                                            Spacer()

                                            Text(formattedFocusDuration(session.durationSeconds))
                                                .font(.subheadline.weight(.semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(.primary)
                                        }

                                        Text(englishDateString(session.completedAt, dateStyle: .medium, timeStyle: .short))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } footer: {
                            Text("Edit a session’s category or exact duration. Every Insights total and chart updates from the corrected record.")
                        }
                    }
                }
            }
            .navigationTitle("Recorded Focus Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FocusSessionEditorView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    let sessionId: String
    let completedAt: Date
    @State private var durationSeconds: Int
    @State private var selectedCategory: String?
    @State private var showingCategories = false

    init(session: FocusSession) {
        sessionId = session.id
        completedAt = session.completedAt
        _durationSeconds = State(initialValue: min(86_399, max(1, session.durationSeconds)))
        _selectedCategory = State(initialValue: session.category)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Completed") {
                    Text(englishDateString(completedAt, dateStyle: .medium, timeStyle: .short))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Time Spent") {
                HStack(spacing: 0) {
                    durationPicker("Hours", selection: durationHours, range: 0...23)
                    Text("h").foregroundStyle(.secondary)
                    durationPicker("Minutes", selection: durationMinutes, range: 0...59)
                    Text("m").foregroundStyle(.secondary)
                    durationPicker("Seconds", selection: durationSecondPart, range: 0...59)
                    Text("s").foregroundStyle(.secondary)
                }
                .frame(height: 145)
            }

            Section {
                Picker("Category", selection: $selectedCategory) {
                    Text("Other").tag(Optional<String>.none)
                    ForEach(store.categories, id: \.self) { category in
                        Text(category).tag(Optional(category))
                    }
                }

                Button("Manage Categories", systemImage: "tag") {
                    showingCategories = true
                }
            } header: {
                Text("Category")
            } footer: {
                Text("Saving recalculates lifetime, day, week, month, year, chart, and category figures.")
            }
        }
        .navigationTitle("Edit Focus Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear {
            guard let selectedCategory,
                  !store.categories.contains(where: {
                      $0.localizedCaseInsensitiveCompare(selectedCategory) == .orderedSame
                  }) else { return }
            self.selectedCategory = nil
        }
        .sheet(isPresented: $showingCategories) {
            CategoryManagerSheet()
        }
        .sensoryFeedback(.selection, trigger: durationSeconds)
    }

    private func durationPicker(
        _ title: String,
        selection: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text(String(format: "%02d", value)).tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var durationHours: Binding<Int> {
        Binding(
            get: { durationSeconds / 3_600 },
            set: { hours in
                durationSeconds = max(1, hours * 3_600 + (durationSeconds % 3_600))
            }
        )
    }

    private var durationMinutes: Binding<Int> {
        Binding(
            get: { (durationSeconds % 3_600) / 60 },
            set: { minutes in
                durationSeconds = max(1, (durationSeconds / 3_600) * 3_600 + minutes * 60 + durationSeconds % 60)
            }
        )
    }

    private var durationSecondPart: Binding<Int> {
        Binding(
            get: { durationSeconds % 60 },
            set: { seconds in
                durationSeconds = max(1, (durationSeconds / 60) * 60 + seconds)
            }
        )
    }

    private func save() {
        store.updateFocusSession(
            id: sessionId,
            durationSeconds: durationSeconds,
            category: selectedCategory
        )
        dismiss()
    }
}

private func focusCategoryName(_ category: String?) -> String {
    guard let category = category?.trimmingCharacters(in: .whitespacesAndNewlines),
          !category.isEmpty else { return "Other" }
    return category
}

private func formattedFocusDuration(_ seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    return String(
        format: "%02d h %02d m %02d s",
        safeSeconds / 3_600,
        (safeSeconds % 3_600) / 60,
        safeSeconds % 60
    )
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
        }
        .padding(18)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
