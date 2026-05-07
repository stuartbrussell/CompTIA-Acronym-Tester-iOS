import Foundation

/// One source JSON file — either bundled or downloaded to the Documents directory.
///
/// The list of available acronym files is driven by `MasterList.json`, which is
/// seeded from the bundle and can be updated via `UpdateManager`. Drop a new JSON
/// into `Resources`, add an entry to the bundled seed, and it will appear as a
/// toggle in Settings for new installs; existing installs pick it up on the next
/// network update check.
struct AcronymList: Identifiable, Hashable {
    let id: String            // stable id used in UserDefaults
    let displayName: String   // shown in Settings
    let resourceName: String  // filename without extension

    // MARK: - Dynamic list from MasterList.json

    /// Loads the list definitions from Documents/MasterList.json (the live,
    /// possibly-updated copy), falling back to the bundled seed if not present.
    /// The #if DEBUG "Test" list is appended unconditionally in debug builds.
    static var all: [AcronymList] {
        var lists: [AcronymList] = loadFromMasterList()

        #if DEBUG
        lists.append(.init(id: "test",
                           displayName: "Test",
                           resourceName: "test"))
        #endif

        return lists
    }

    // MARK: - Private helpers

    private static func loadFromMasterList() -> [AcronymList] {
        // Prefer the downloaded copy in Documents; fall back to the bundle seed.
        let docsURL = URL.documentsDirectory.appendingPathComponent("MasterList.json")
        if let master = decodeMasterList(from: docsURL) {
            return master.files.map { AcronymList(id: $0.id,
                                                  displayName: $0.displayName,
                                                  resourceName: $0.resourceName) }
        }
        if let bundleURL = Bundle.main.url(forResource: "MasterList", withExtension: "json"),
           let master = decodeMasterList(from: bundleURL) {
            return master.files.map { AcronymList(id: $0.id,
                                                  displayName: $0.displayName,
                                                  resourceName: $0.resourceName) }
        }
        // Last-resort hard-coded fallback (should never happen with a valid build).
        assertionFailure("AcronymList: could not load MasterList.json from Documents or bundle")
        return [
            .init(id: "aplus",   displayName: "CompTIA A+ (220-1101/1102)", resourceName: "APlus"),
            .init(id: "netplus", displayName: "CompTIA Network+ (N10-009)", resourceName: "NetworkPlus"),
            .init(id: "ports",   displayName: "Network Ports",              resourceName: "NetworkPorts"),
        ]
    }

    private static func decodeMasterList(from url: URL) -> MasterList? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MasterList.self, from: data)
    }
}
