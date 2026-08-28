import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "calendar") }
            TaskListView().tabItem { Label("Tasks", systemImage: "checkmark.circle") }
            FocusView().tabItem { Label("Focus", systemImage: "timer") }
            InsightsView().tabItem { Label("Insights", systemImage: "chart.bar") }
        }
    }
}

private struct TodayView: View {
    @EnvironmentObject var store: FlowtimeStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(24..<31) { day in
                            VStack(spacing: 8) {
                                Text(["M","T","W","T","F","S","S"][day - 24]).font(.caption2).foregroundStyle(.secondary)
                                Text("\(day)").font(.subheadline.bold()).frame(width: 36, height: 36).background(day == 28 ? Color.accentColor : .clear).foregroundStyle(day == 28 ? .white : .primary).clipShape(Circle())
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    FocusSummaryCard()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT").font(.caption2.bold()).foregroundStyle(.secondary)
                        ForEach(store.tasks.filter { !$0.done }.prefix(3)) { task in TaskCell(task: task) }
                    }.padding(18).background(.background).clipShape(RoundedRectangle(cornerRadius: 20))
                }.padding()
            }.background(Color(.systemGroupedBackground)).navigationTitle("Good afternoon 👋")
        }
    }
}

private struct FocusSummaryCard: View {
    @EnvironmentObject var store: FlowtimeStore
    var body: some View {
        VStack(spacing: 15) {
            Text("FOCUS SESSION").font(.caption2.bold()).foregroundStyle(.white.opacity(0.6))
            Text("Website redesign").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Text(String(format: "%02d:%02d", store.focusSeconds / 60, store.focusSeconds % 60)).font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            Button { store.isFocusing.toggle() } label: { Image(systemName: store.isFocusing ? "pause.fill" : "play.fill").frame(width: 52, height: 52).background(.white).foregroundStyle(.black).clipShape(Circle()) }
        }.frame(maxWidth: .infinity).padding(24).background(LinearGradient(colors: [Color(red:0.12,green:0.18,blue:0.29), Color(red:0.05,green:0.09,blue:0.16)], startPoint:.topLeading, endPoint:.bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct TaskCell: View {
    @EnvironmentObject var store: FlowtimeStore
    let task: FlowTask
    var body: some View { HStack { Button { store.toggle(task) } label: { Image(systemName: task.done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain); VStack(alignment:.leading) { Text(task.title).strikethrough(task.done); Text("\(task.dueAt ?? "Anytime") · \(task.category)").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("\(task.estimate)m").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 11) }
}

private struct TaskListView: View {
    @EnvironmentObject var store: FlowtimeStore
    @State private var newTitle = ""
    var body: some View { NavigationStack { List { Section { HStack { TextField("Add a task", text:$newTitle); Button("Add") { guard !newTitle.isEmpty else{return}; store.addTask(title:newTitle); newTitle="" } } }; Section("Your tasks") { ForEach(store.tasks) { task in TaskCell(task:task) } } }.navigationTitle("Tasks") } }
}

private struct FocusView: View { var body: some View { NavigationStack { VStack { Spacer(); FocusSummaryCard().padding(); Spacer() }.background(Color(.systemGroupedBackground)).navigationTitle("Focus") } } }
private struct InsightsView: View { let values=[4.2,5.5,3.1,6.4,4.8,2.2,1.4]; var body: some View { NavigationStack { VStack(alignment:.leading,spacing:20) { Text("18h 24m").font(.system(size:38,weight:.bold)); Text("Focused this week").foregroundStyle(.secondary); HStack(alignment:.bottom,spacing:12) { ForEach(Array(values.enumerated()),id:\.offset) { index,value in VStack { RoundedRectangle(cornerRadius:5).fill(Color.accentColor).frame(height:value*28); Text(["M","T","W","T","F","S","S"][index]).font(.caption2).foregroundStyle(.secondary) } } }.frame(maxWidth:.infinity,maxHeight:220,alignment:.bottom); Spacer() }.padding().navigationTitle("Insights") } } }
