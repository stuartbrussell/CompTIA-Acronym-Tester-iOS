import SwiftUI

@main
struct CompTIAAcronymTesterApp: App {
    @StateObject private var store = QuizStore()

    var body: some Scene {
        WindowGroup {
            QuizView()
                .environmentObject(store)
        }
    }
}
