import Foundation

// MARK: - masterList.json schema
//
// The bundled seed and any downloaded update both use this shape:
//
// {
//   "version": 1,
//   "files": [
//     {
//       "id":           "aplus",
//       "displayName":  "CompTIA A+ (220-1101/1102)",
//       "resourceName": "APlus",
//       "link":         "https://example.com/acronyms/APlus.json",
//       "version":      1
//     },
//     ...
//   ]
// }
//
// `version` on the root object is the master-list schema version.
// `version` on each file entry is that individual acronym file's data version.

/// Top-level object decoded from `masterList.json`.
struct MasterList: Codable {
    /// Schema/data version of this master list. The app checks this against
    /// the bundled copy to decide whether a download is available.
    let version: Int
    /// Ordered array of acronym-file descriptors shown in Settings.
    let files: [RemoteFileEntry]
}

/// One acronym-file descriptor inside `masterList.json`.
struct RemoteFileEntry: Codable, Identifiable, Hashable {
    /// Stable identifier — must match the `id` used in UserDefaults
    /// (e.g. "aplus", "netplus", "ports").
    let id: String
    /// Human-readable name shown in Settings toggles.
    let displayName: String
    /// Filename without extension used both as the bundle resource name and
    /// as the filename when written to the Documents directory.
    let resourceName: String
    /// Absolute HTTPS URL from which the versioned acronym JSON is fetched.
    let link: String
    /// Data version of this acronym file. Compared against the version
    /// embedded in the file on disk to decide whether a re-download is needed.
    let version: Int
}
