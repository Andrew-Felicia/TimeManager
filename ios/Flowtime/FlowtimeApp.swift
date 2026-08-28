import SwiftUI

@main
struct FlowtimeApp: App {
    @StateObject private var store = FlowtimeStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .tint(Color(red: 0.31, green: 0.49, blue: 0.95))
        }
    }
}
