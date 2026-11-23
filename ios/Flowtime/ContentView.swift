import SwiftUI
import Charts
import UIKit
import UserNotifications

struct ContentView: View {
    @State private var selectedTab = 0

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
        .toolbarBackground(.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
                    Text("Swipe left to delete. Existing events and tasks will be moved to another category.")
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

private struct FocusSummaryCard: View {
    @EnvironmentObject private var store: FlowtimeStore

    var body: some View {
        VStack(spacing: 15) {
            Text(store.isFocusing ? "FOCUSING NOW" : "FOCUS SESSION")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.6))

            Text(store.focusLabel.isEmpty ? "Untitled focus" : store.focusLabel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.02, store.focusProgress))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: store.focusProgress)
                Text(formattedTime(store.displayedSeconds))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 172, height: 172)

            HStack(spacing: 24) {
                Button { store.resetFocus() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Reset focus session")

                Button { store.toggleFocus() } label: {
                    Image(systemName: store.isFocusing ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 58, height: 58)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(Circle())
                }
                .accessibilityLabel(store.isFocusing ? "Pause focus session" : "Start focus session")

                Button { store.finishFocus() } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Finish and save focus session")
            }
            .foregroundStyle(.white)

            Text(store.isFocusing ? "Tap pause to take a break" : "Your progress is saved when you stop")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.18, blue: 0.29), Color(red: 0.05, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func formattedTime(_ seconds: Int) -> String {
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TaskCell: View {
    @EnvironmentObject private var store: FlowtimeStore
    let task: FlowTask

    var body: some View {
        HStack(spacing: 12) {
            Button { store.toggle(task) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.green : Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                HStack(spacing: 8) {
                    Label("\(task.estimate)m", systemImage: "timer")
                    if let scheduledAt = task.scheduledAt {
                        Label(scheduledAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }
                    if !task.subtasks.isEmpty {
                        Label("\(task.subtasks.filter(\.done).count)/\(task.subtasks.count)", systemImage: "checklist")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if task.deadline != nil {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.red : Color.orange)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var isOverdue: Bool {
        guard let deadline = task.deadline, !task.done else { return false }
        return deadline < Calendar.current.startOfDay(for: Date())
    }
}

private struct TaskEditorTarget: Identifiable {
    let id = UUID()
    let task: FlowTask?
    let listId: String
}

private struct TaskListView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var selectedListId: String? = "inbox"
    @State private var editorTarget: TaskEditorTarget?
    @State private var showingListManager = false

    private var visibleTasks: [FlowTask] {
        store.tasks
            .filter { selectedListId == nil || $0.listId == selectedListId }
            .sorted {
                if $0.done != $1.done { return !$0.done }
                return ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture)
            }
    }

    private var selectedListName: String {
        guard let selectedListId else { return "All tasks" }
        return store.taskLists.first(where: { $0.id == selectedListId })?.name ?? "Tasks"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TaskListChip(title: "All", count: store.tasks.count, selected: selectedListId == nil) {
                            selectedListId = nil
                        }
                        ForEach(store.taskLists) { list in
                            TaskListChip(
                                title: list.name,
                                count: store.tasks.filter { $0.listId == list.id }.count,
                                selected: selectedListId == list.id
                            ) { selectedListId = list.id }
                        }
                        Button { showingListManager = true } label: {
                            Image(systemName: "plus").frame(width: 34, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Manage task lists")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)

                if visibleTasks.isEmpty {
                    ContentUnavailableView(
                        "No tasks in \(selectedListName)",
                        systemImage: "checklist",
                        description: Text("Create a task, then add details, dates, and subtasks.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(visibleTasks) { task in
                            TaskCell(task: task)
                                .onTapGesture {
                                    editorTarget = TaskEditorTarget(task: task, listId: task.listId)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.delete(task) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { store.toggle(task) } label: {
                                        Label(task.done ? "Reopen" : "Complete", systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New task", systemImage: "checkmark.circle") {
                            editorTarget = TaskEditorTarget(task: nil, listId: selectedListId ?? store.taskLists.first?.id ?? "inbox")
                        }
                        Button("Manage lists", systemImage: "list.bullet.rectangle") { showingListManager = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create task or list")
                }
            }
            .sheet(item: $editorTarget) { target in
                TaskEditorSheet(task: target.task, defaultListId: target.listId)
            }
            .sheet(isPresented: $showingListManager) { TaskListManagerSheet() }
        }
    }
}

private struct TaskListChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(selected ? Color.accentColor : Color.secondary.opacity(0.18))
        .foregroundStyle(selected ? .white : .primary)
    }
}

private struct TaskEditorSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    let task: FlowTask?
    @State private var title: String
    @State private var details: String
    @State private var estimateText: String
    @State private var listId: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var hasSchedule: Bool
    @State private var scheduledAt: Date
    @State private var subtasks: [FlowSubtask]
    @State private var newSubtask = ""
    @FocusState private var titleFocused: Bool

    init(task: FlowTask?, defaultListId: String) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _estimateText = State(initialValue: task.map { String($0.estimate) } ?? "")
        _listId = State(initialValue: task?.listId ?? defaultListId)
        _hasDeadline = State(initialValue: task?.deadline != nil)
        _deadline = State(initialValue: task?.deadline ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        _hasSchedule = State(initialValue: task?.scheduledAt != nil)
        _scheduledAt = State(initialValue: task?.scheduledAt ?? Date())
        _subtasks = State(initialValue: task?.subtasks ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $title)
                        .focused($titleFocused)
                    TextEditor(text: $details)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Add details")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Section("Organize") {
                    Picker("Task list", selection: $listId) {
                        ForEach(store.taskLists) { list in Text(list.name).tag(list.id) }
                    }
                    HStack {
                        TextField("Estimated time", text: $estimateText)
                            .keyboardType(.numberPad)
                        Text("minutes")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ForEach([15, 25, 50, 90], id: \.self) { minutes in
                            Button("\(minutes)m") { estimateText = String(minutes) }
                                .buttonStyle(.bordered)
                        }
                    }
                    Text("Required · between 1 minute and 8 hours")
                        .font(.caption)
                        .foregroundStyle(estimateMinutes == nil ? Color.red : Color.secondary)
                }
                Section("Dates") {
                    Toggle("Add deadline", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                    }
                    Toggle("Add date and time", isOn: $hasSchedule.animation())
                    if hasSchedule {
                        DatePicker("Scheduled", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("Subtasks") {
                    ForEach($subtasks) { $subtask in
                        HStack {
                            Button { subtask.done.toggle() } label: {
                                Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(subtask.done ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            TextField("Subtask", text: $subtask.title)
                                .strikethrough(subtask.done)
                        }
                    }
                    .onDelete { subtasks.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add a subtask", text: $newSubtask)
                            .submitLabel(.done)
                            .onSubmit(addSubtask)
                        Button("Add", action: addSubtask)
                            .disabled(newSubtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(task == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || estimateMinutes == nil)
                }
            }
            .onAppear {
                if !store.taskLists.contains(where: { $0.id == listId }) { listId = store.taskLists.first?.id ?? "inbox" }
                titleFocused = true
            }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let estimate = estimateMinutes else { return }
        if var updated = task {
            updated.title = title
            updated.details = details
            updated.estimate = estimate
            updated.listId = listId
            updated.deadline = hasDeadline ? deadline : nil
            updated.scheduledAt = hasSchedule ? scheduledAt : nil
            updated.subtasks = subtasks
            store.updateTask(updated)
        } else {
            store.addTask(
                title: title,
                listId: listId,
                details: details,
                estimate: estimate,
                deadline: hasDeadline ? deadline : nil,
                scheduledAt: hasSchedule ? scheduledAt : nil,
                subtasks: subtasks
            )
        }
        dismiss()
    }

    private var estimateMinutes: Int? {
        guard let value = Int(estimateText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...480).contains(value) else { return nil }
        return value
    }

    private func addSubtask() {
        let cleanTitle = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        subtasks.append(FlowSubtask(id: UUID().uuidString, title: cleanTitle, done: false))
        newSubtask = ""
    }
}

private struct TaskListManagerSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New list") {
                    HStack {
                        TextField("List name", text: $newListName)
                            .submitLabel(.done)
                            .onSubmit(addList)
                        Button("Add", action: addList)
                            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    ForEach(store.taskLists) { list in
                        HStack {
                            Label(list.name, systemImage: list.id == "inbox" ? "tray" : "list.bullet")
                            Spacer()
                            Text("\(store.tasks.filter { $0.listId == list.id }.count)")
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if list.id != "inbox" {
                                Button(role: .destructive) { store.deleteTaskList(list) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Your lists")
                } footer: {
                    Text("Deleting a list moves its tasks to Inbox.")
                }
            }
            .navigationTitle("Task lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func addList() {
        _ = store.addTaskList(newListName)
        newListName = ""
    }
}

private struct FocusView: View {
    @EnvironmentObject private var store: FlowtimeStore

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        Picker("Focus mode", selection: Binding(
                            get: { store.focusMode },
                            set: { store.setFocusMode($0) }
                        )) {
                            ForEach(FocusMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if store.focusMode == .timer {
                            ClockTimerView()
                        } else {
                            stopwatchTaskPicker
                            FocusSummaryCard()

                            HStack(spacing: 12) {
                                StatTile(value: formattedDuration(store.weeklyFocusSeconds), label: "This week")
                                StatTile(value: "\(store.sessionCount)", label: "Sessions")
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(store.focusMode == .timer ? "Timers" : "Stopwatch")
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
    }

    private var activeTasks: [FlowTask] {
        store.tasks.filter { !$0.done }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var stopwatchTaskPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.accentColor)
            Picker("Focus task", selection: Binding(
                get: { store.selectedFocusTaskId },
                set: { store.selectFocusTask($0) }
            )) {
                Text("No task (general focus)").tag(String?.none)
                ForEach(activeTasks) { task in
                    Text("\(task.title) · \(task.estimate) min").tag(Optional(task.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .disabled(store.isAnyFocusRunning || activeTasks.isEmpty)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }
}

private struct ClockTimerView: View {
    @EnvironmentObject private var store: FlowtimeStore
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var pickerIsReady = false
    @State private var showingTimerEndOptions = false
    private let recentDurations = [1_500, 3_000, 5_400]

    var body: some View {
        VStack(spacing: 28) {
            if timerIsActive {
                activeTimerDisplay
            } else {
                HStack(spacing: 0) {
                    timerWheel(title: "hours", selection: $hours, values: 0...23)
                    timerWheel(title: "min", selection: $minutes, values: 0...59)
                    timerWheel(title: "sec", selection: $seconds, values: 0...59)
                }
                .frame(height: 215)
                .sensoryFeedback(.selection, trigger: hours)
                .sensoryFeedback(.selection, trigger: minutes)
                .sensoryFeedback(.selection, trigger: seconds)
                .onChange(of: hours) { _, _ in updateDurationFromPicker() }
                .onChange(of: minutes) { _, _ in updateDurationFromPicker() }
                .onChange(of: seconds) { _, _ in updateDurationFromPicker() }
            }

            timerOptions
            timerControls
            recentTimers
        }
        .padding(.horizontal)
        .onAppear {
            loadPickerDuration(store.timerTargetSeconds)
            pickerIsReady = true
        }
        .onChange(of: store.timerTargetSeconds) { _, newValue in
            guard !timerIsActive else { return }
            loadPickerDuration(newValue)
        }
        .sheet(isPresented: $showingTimerEndOptions) {
            TimerEndOptionsSheet()
        }
    }

    private var timerIsActive: Bool {
        store.isFocusing || store.timerHasStarted
    }

    private var totalPickerSeconds: Int {
        hours * 3_600 + minutes * 60 + seconds
    }

    private var activeTimerDisplay: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.13), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, store.focusProgress))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: store.focusProgress)

            VStack(spacing: 7) {
                Text(clockTime(store.displayedSeconds))
                    .font(.system(size: store.displayedSeconds >= 3_600 ? 45 : 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text(store.focusLabel.isEmpty ? "Timer" : store.focusLabel)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(store.isFocusing ? "Ends \(expectedEndTime)" : "Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(width: 285, height: 285)
        .frame(maxWidth: .infinity)
    }

    private var timerOptions: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Label")
                TextField("Timer", text: Binding(
                    get: { store.focusLabel },
                    set: { store.setFocusLabel($0) }
                ))
                .multilineTextAlignment(.trailing)
                .disabled(timerIsActive)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider().overlay(Color.white.opacity(0.12))

            Button {
                showingTimerEndOptions = true
            } label: {
                HStack {
                    Text("When Timer Ends")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(store.timerEndAlert.rawValue)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var timerControls: some View {
        HStack {
            ClockControlButton(
                title: "Cancel",
                color: .gray,
                isEnabled: timerIsActive
            ) {
                store.resetFocus()
                loadPickerDuration(store.timerTargetSeconds)
            }

            Spacer()

            ClockControlButton(
                title: store.isFocusing ? "Pause" : (store.timerHasStarted ? "Resume" : "Start"),
                color: timerIsActive ? .orange : .green,
                isEnabled: timerIsActive || totalPickerSeconds > 0
            ) {
                if !timerIsActive {
                    store.setTimerDuration(seconds: totalPickerSeconds)
                }
                store.toggleFocus()
            }
        }
        .padding(.horizontal, 4)
    }

    private var recentTimers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recents")
                .font(.title2.bold())

            VStack(spacing: 0) {
                ForEach(Array(recentDurations.enumerated()), id: \.element) { index, duration in
                    Button {
                        store.setTimerDuration(seconds: duration)
                        loadPickerDuration(duration)
                        store.toggleFocus()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shortDuration(duration))
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                Text("Focus")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                                .frame(width: 38, height: 38)
                                .background(Color.green.opacity(0.18))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 66)
                    }
                    .buttonStyle(.plain)
                    .disabled(timerIsActive)

                    if index < recentDurations.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(white: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
    }

    private var expectedEndTime: String {
        (store.timerExpectedEndDate ?? Date().addingTimeInterval(TimeInterval(store.displayedSeconds)))
            .formatted(date: .omitted, time: .shortened)
    }

    private func timerWheel(
        title: String,
        selection: Binding<Int>,
        values: ClosedRange<Int>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text("\(value)")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.white)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
                .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityLabel(title)
    }

    private func updateDurationFromPicker() {
        guard pickerIsReady, !timerIsActive, totalPickerSeconds > 0 else { return }
        store.setTimerDuration(seconds: totalPickerSeconds)
    }

    private func loadPickerDuration(_ duration: Int) {
        let clamped = min(max(1, duration), 86_399)
        hours = clamped / 3_600
        minutes = (clamped % 3_600) / 60
        seconds = clamped % 60
    }

    private func clockTime(_ duration: Int) -> String {
        if duration >= 3_600 {
            return String(format: "%d:%02d:%02d", duration / 3_600, (duration % 3_600) / 60, duration % 60)
        }
        return String(format: "%02d:%02d", duration / 60, duration % 60)
    }

    private func shortDuration(_ duration: Int) -> String {
        let hours = duration / 3_600
        let minutes = (duration % 3_600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr" }
        return "\(minutes) min"
    }
}

private struct TimerEndOptionsSheet: View {
    @EnvironmentObject private var store: FlowtimeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TimerEndAlert.allCases) { option in
                        Button {
                            store.setTimerEndAlert(option)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(option == .defaultSound ? "Long alarm sound and haptics" : "Notification without sound")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.timerEndAlert == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
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
                        Text("To keep the banner on screen until you tap it, choose Banners and set Banner Style to Persistent in iPhone Settings.")
                    }
                }
            }
            .navigationTitle("When Timer Ends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium])
    }
}

private struct ClockControlButton: View {
    let title: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(isEnabled ? color : Color.secondary)
                .frame(width: 76, height: 76)
                .background((isEnabled ? color : Color.gray).opacity(isEnabled ? 0.18 : 0.1))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
