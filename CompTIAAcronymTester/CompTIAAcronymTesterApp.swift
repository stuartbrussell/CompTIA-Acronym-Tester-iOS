import SwiftUI

@main
struct CompTIAAcronymTesterApp: App {
    /// Seeding and update management run before anything else.
    private let updateManager: UpdateManager = {
        let mgr = UpdateManager()
        // Synchronously copy bundled JSON files to Documents so that
        // AcronymList.all and JSONLoader always find them on first launch.
        mgr.seedIfNeeded()
        return mgr
    }()

    @StateObject private var store: QuizStore

    init() {
        // `updateManager` is already initialised (and seeding is done) by the
        // time this initialiser runs because Swift evaluates stored-property
        // initialisers before `init()` bodies. `QuizStore()` is therefore safe
        // to construct here — the Documents files exist.
        _store = StateObject(wrappedValue: QuizStore())
    }

    var body: some Scene {
        WindowGroup {
            QuizView()
                .environmentObject(store)
                .environmentObject(updateManager)
                .task {
                    // Wire up store reference so UpdateManager can call reload()
                    // after applying an update, then kick off the network check.
                    updateManager.configure(quizStore: store)
                    updateManager.checkForUpdates()
                }
        }
    }
}
