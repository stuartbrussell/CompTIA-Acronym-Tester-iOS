import Foundation

/// One source JSON file bundled with the app.
///
/// The CSVs on the Python side are the canonical data source; the JSON files
/// are generated from them and bundled here. Drop a new JSON into `Resources`,
/// add an entry here, and it appears as a toggle in Settings.
struct AcronymList: Identifiable, Hashable {
    let id: String            // stable id used in UserDefaults
    let displayName: String   // shown in Settings
    let resourceName: String  // filename in the app bundle, without .json

    static var all: [AcronymList] {
        var lists: [AcronymList] = [
            .init(id: "aplus",
                  displayName: "CompTIA A+ (220-1101/1102)",
                  resourceName: "APlus"),
            .init(id: "netplus",
                  displayName: "CompTIA Network+ (N10-009)",
                  resourceName: "NetworkPlus"),
            .init(id: "ports",
                  displayName: "Network Ports",
                  resourceName: "NetworkPorts"),
        ]
        #if DEBUG
        lists.append(.init(id: "test",
                           displayName: "Test",
                           resourceName: "test"))
        #endif
        return lists
    }
}
