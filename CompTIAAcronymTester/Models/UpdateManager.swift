import Foundation
import Network
import Combine

// MARK: - URL constants
// private let baseURL = "https://raw.githubusercontent.com/stuartbrussell/CompTIA-Acronym-Tester-iOS/refs/heads/main/CompTIAAcronymTester/Resources"
private let baseURL = "https://raw.githubusercontent.com/stuartbrussell/CompTIA-Acronym-Tester-data/refs/heads/main/CompTIAAcronymTester/Resources"
private let masterListURL = URL(string: "\(baseURL)/MasterList.json")!

// MARK: - UpdateManager

/// Checks for acronym-data updates, downloads new files in parallel, and
/// atomically promotes them to the Documents directory once the user confirms.
///
/// **Lifecycle**
/// 1. At app startup, `CompTIAAcronymTesterApp` calls `seedIfNeeded()` synchronously
///    so that the Documents copies always exist before `QuizStore` reads them.
/// 2. After the UI is ready, `CompTIAAcronymTesterApp` calls `checkForUpdates()`.
///    If a new master-list version is available and the network is reachable,
///    all acronym files are downloaded into a staging area.
/// 3. If all downloads succeed, `updateReady` becomes `true`, which causes
///    `QuizView` to show the Update alert.
/// 4. The user chooses:
///    - **Update Now** → `applyPendingUpdate()` is called; files are atomically
///      moved to Documents; `QuizStore.reload()` picks up the new data.
///    - **Later** → nothing happens; the staged files remain for this session.
///    - **Skip This Version** → the incoming master-list version is recorded in
///      UserDefaults; the check is skipped on future launches for that version.
///
/// **Error handling**
/// Any single download failure aborts the whole update (no partial replacements).
/// The staging area is cleaned up and the user sees no alert.
final class UpdateManager: ObservableObject {

    // MARK: - Published state

    /// True while downloads are in progress (drives a spinner if desired).
    @Published private(set) var isChecking: Bool = false
    /// True once a complete set of files has been staged and is ready to apply.
    /// Exposed as read-write so `.alert(isPresented:)` can reset it via binding;
    /// external writes are effectively no-ops because the value is only set to
    /// `true` by internal logic and the alert dismisses by setting it to `false`.
    @Published var updateReady: Bool = false
    /// Human-readable description set when `updateReady` is true.
    @Published private(set) var updateDescription: String = ""

    // MARK: - Dependencies (injected for testability)

    private let session: URLSession
    private weak var quizStore: QuizStore?

    // MARK: - Internal state

    /// The downloaded master list waiting to be committed.
    private var pendingMasterList: MasterList?
    /// Path to the staging folder inside Library/Caches.
    private static var stagingURL: URL {
        URL.cachesDirectory.appendingPathComponent("PendingDownloads", isDirectory: true)
    }

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
    }

    func configure(quizStore: QuizStore) {
        self.quizStore = quizStore
    }

    // MARK: - Seeding

    /// Copies bundled JSON files to the Documents directory if they don't
    /// already exist there. Must be called synchronously before `QuizStore`
    /// is initialised so that `AcronymList.all` and `JSONLoader` find the files.
    func seedIfNeeded() {
        seedFile(named: "MasterList")

        // Seed individual acronym files listed in the bundled master list.
        guard let bundleURL = Bundle.main.url(forResource: "MasterList", withExtension: "json"),
              let data = try? Data(contentsOf: bundleURL),
              let master = try? JSONDecoder().decode(MasterList.self, from: data) else {
            return
        }
        for entry in master.files {
            seedFile(named: entry.resourceName)
        }
    }

    private func seedFile(named name: String) {
        let dest = URL.documentsDirectory.appendingPathComponent("\(name).json")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        guard let src = Bundle.main.url(forResource: name, withExtension: "json") else { return }
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    // MARK: - Update check

    /// Checks the remote master list and downloads all updated acronym files
    /// into a staging area. If everything succeeds, sets `updateReady = true`.
    /// Safe to call from any context; all UI updates are dispatched to the main actor.
    func checkForUpdates() {
        guard !isChecking else { return }

        Task {
            await MainActor.run { self.isChecking = true }
            defer { Task { await MainActor.run { self.isChecking = false } } }

            // Network reachability — quick synchronous check via NWPathMonitor.
            guard isNetworkAvailable() else { return }

            do {
                // 1. Fetch the remote master list.
                let remoteMaster = try await fetchMasterList()

                // 2. Compare against the current Documents copy.
                let localMasterURL = URL.documentsDirectory.appendingPathComponent("MasterList.json")
                let localVersion = JSONLoader.version(at: localMasterURL) ?? 0

                guard remoteMaster.version > localVersion else { return }

                // 3. Check whether the user has skipped this version.
                if Defaults.skippedMasterListVersion == remoteMaster.version { return }

                // 4. Download all files into the staging area.
                try await downloadAll(entries: remoteMaster.files)

                // 5. Stage the master list itself.
                let stagingMasterURL = Self.stagingURL.appendingPathComponent("MasterList.json")
                let masterData = try JSONEncoder().encode(remoteMaster)
                try masterData.write(to: stagingMasterURL, options: .atomic)

                // 6. Publish the pending update on the main actor.
                await MainActor.run {
                    self.pendingMasterList = remoteMaster
                    let newListCount = remoteMaster.files
                        .filter { entry in
                            let localURL = URL.documentsDirectory.appendingPathComponent("\(entry.resourceName).json")
                            let localVer = JSONLoader.version(at: localURL) ?? 0
                            return entry.version > localVer
                        }.count
                    self.updateDescription = newListCount == 1
                        ? "1 acronym list has been updated."
                        : "\(newListCount) acronym lists have been updated."
                    self.updateReady = true
                }
            } catch {
                // Non-fatal — clean up staging and stay silent.
                cleanUpStaging()
                print("UpdateManager: update check failed — \(error)")
            }
        }
    }

    // MARK: - Apply / dismiss

    /// Atomically promotes staged files to the Documents directory and asks
    /// `QuizStore` to reload. Call this when the user taps "Update Now".
    func applyPendingUpdate() {
        guard updateReady else { return }
        do {
            let fm = FileManager.default
            let staged = try fm.contentsOfDirectory(at: Self.stagingURL,
                                                    includingPropertiesForKeys: nil)
            for src in staged {
                let dest = URL.documentsDirectory.appendingPathComponent(src.lastPathComponent)
                // Atomic replace: remove destination first so we can rename in.
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: src, to: dest)
            }
            quizStore?.reload()
            resetState()
        } catch {
            print("UpdateManager: failed to apply update — \(error)")
            cleanUpStaging()
            resetState()
        }
    }

    /// User chose "Later" — keep staged files but dismiss the alert.
    func dismissUpdate() {
        updateReady = false
        // Staged files remain; `pendingMasterList` is preserved so the user
        // can be offered the update again if the app is still running.
    }

    /// User chose "Skip This Version" — record the version and dismiss.
    func skipUpdate() {
        if let version = pendingMasterList?.version {
            Defaults.skippedMasterListVersion = version
        }
        cleanUpStaging()
        resetState()
    }

    // MARK: - Private helpers

    private func fetchMasterList() async throws -> MasterList {
        let (data, response) = try await session.data(from: masterListURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badHTTPStatus
        }
        return try JSONDecoder().decode(MasterList.self, from: data)
    }

    /// Download every entry in `entries` in parallel into the staging directory.
    /// Throws if any single download fails (all-or-nothing guarantee).
    private func downloadAll(entries: [RemoteFileEntry]) async throws {
        let fm = FileManager.default
        // Recreate staging dir cleanly.
        try? fm.removeItem(at: Self.stagingURL)
        try fm.createDirectory(at: Self.stagingURL,
                               withIntermediateDirectories: true)

        // Parallel downloads via TaskGroup.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask {
                    try await self.downloadFile(entry: entry)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Download one acronym file, retrying once on transient failure.
    private func downloadFile(entry: RemoteFileEntry) async throws {
        guard let url = URL(string: "\(baseURL)/\(entry.resourceName).json") else {
            throw UpdateError.invalidURL(entry.resourceName)
        }
        var lastError: Error?
        for attempt in 1...2 {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw UpdateError.badHTTPStatus
                }
                let dest = Self.stagingURL.appendingPathComponent("\(entry.resourceName).json")
                try data.write(to: dest, options: .atomic)
                return  // success
            } catch {
                lastError = error
                if attempt < 2 {
                    // Brief back-off before retry.
                    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 s
                }
            }
        }
        throw lastError ?? UpdateError.badHTTPStatus
    }

    private func isNetworkAvailable() -> Bool {
        let monitor = NWPathMonitor()
        var satisfied = false
        let sema = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            satisfied = path.status == .satisfied
            sema.signal()
        }
        monitor.start(queue: DispatchQueue(label: "UpdateManager.networkCheck"))
        sema.wait()
        monitor.cancel()
        return satisfied
    }

    private func cleanUpStaging() {
        try? FileManager.default.removeItem(at: Self.stagingURL)
    }

    private func resetState() {
        updateReady = false
        updateDescription = ""
        pendingMasterList = nil
    }

    // MARK: - UserDefaults

    private enum Defaults {
        private static let key = "skippedMasterListVersion"
        static var skippedMasterListVersion: Int {
            get { UserDefaults.standard.integer(forKey: key) }
            set { UserDefaults.standard.set(newValue, forKey: key) }
        }
    }
}

// MARK: - Errors

private enum UpdateError: Error {
    case badHTTPStatus
    case invalidURL(String)
}
