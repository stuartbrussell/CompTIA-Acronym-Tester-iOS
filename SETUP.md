# CompTIA Acronym Tester — iOS Setup

This folder contains the SwiftUI source for the iPhone port of the CompTIA Acronym Tester. It's laid out the way the files should live inside an Xcode project; you create the project in Xcode and drag these files in.

## What's in this folder

```
CompTIAAcronymTester/
├── CompTIAAcronymTesterApp.swift       # @main App entry point
├── Models/
│   ├── Acronym.swift                   # Display model (merged by key)
│   ├── AcronymList.swift               # List catalog (JSON → display name)
│   ├── CSVLoader.swift                 # Defines RawAcronymRow (CSV loader retired)
│   ├── JSONLoader.swift                # Loads acronym data from bundled JSON files
│   └── QuizStore.swift                 # Single ObservableObject for all state
├── Views/
│   ├── QuizView.swift                  # Main quiz screen
│   ├── SettingsView.swift              # Lists, strict mode, length, review, reset
│   └── SafariView.swift                # SFSafariViewController wrapper
└── Resources/
    ├── APlus.csv                       # (source of truth — Python side)
    ├── APlus.json                      # A+ 220-1101/1102 acronyms — used by the app
    ├── NetworkPlus.csv                 # (source of truth — Python side)
    ├── NetworkPlus.json                # Network+ N10-009 acronyms — used by the app
    ├── NetworkPorts.csv                # (source of truth — Python side)
    └── NetworkPorts.json               # Network ports — used by the app
```

The iOS app reads the **JSON files**. The CSVs remain the canonical data on the Python side; when you edit a CSV there, regenerate the matching JSON and drop it into `Resources/`. The JSON schema is `[{"itemkey":…,"itemvalue":…,"itemlink":…,"strict":…}]` (the `strict` field is optional — rows without it are treated as in-scope).

## Creating the Xcode project

1. Open **Xcode 26.2**. File → New → Project…
2. Choose **iOS → App**. Click Next.
3. Fill in:
   - Product Name: `CompTIAAcronymTester`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Include Tests: your call (leave unchecked for now)
   - Minimum Deployment: **iOS 17.0** or newer (the code uses `topBarTrailing`, `LabeledContent`, and the `#Preview` macro, which need iOS 17 / Xcode 15+).
4. Save it somewhere. Xcode will create a folder like `CompTIAAcronymTester/` containing a `CompTIAAcronymTester.xcodeproj` and a same-named inner folder with a stub `CompTIAAcronymTesterApp.swift` and `ContentView.swift`.
5. **Delete** the stub `CompTIAAcronymTesterApp.swift` and `ContentView.swift` that Xcode generated (right-click → Delete → "Move to Trash"). You're about to replace them.
6. In Finder, open the `CompTIAAcronymTester/` folder from this deliverable.
7. Drag these items onto the inner folder in Xcode's Project Navigator (the one with the orange-ish icon, not the top-level project):
   - `CompTIAAcronymTesterApp.swift`
   - The `Models/` folder
   - The `Views/` folder
   - The `Resources/` folder
8. In the add-files dialog that appears, make sure:
   - **Copy items if needed** is checked
   - **Create groups** is selected (not "Create folder references")
   - The CompTIAAcronymTester **target** is checked
9. Click Finish.
10. Select the three `.json` files in the Project Navigator. In the File Inspector on the right, confirm **Target Membership → CompTIAAcronymTester** is checked. (This is the most common thing people forget — without it, the JSONs won't be copied into the app bundle and the app will launch with no data.)

## Building to your iPhone

1. Plug the iPhone in. Unlock it. Tap **Trust** on the "Trust this computer?" prompt if it appears.
2. In Xcode's toolbar, change the run destination from a simulator to your device.
3. Sign the app:
   - Project → Signing & Capabilities
   - **Automatically manage signing** = on
   - **Team** = your personal Apple ID team (if it's not listed, Xcode → Settings → Accounts → add your Apple ID, then come back)
   - **Bundle Identifier**: change `com.yourname.CompTIAAcronymTester` to something unique to you. Free personal accounts need a bundle ID no one else on your account has used.
4. Enable Developer Mode on the iPhone: **Settings → Privacy & Security → Developer Mode → On** (the phone will reboot).
5. First run after reboot: **Settings → General → VPN & Device Management → your Apple ID → Trust**.
6. Hit ▶ Run (Cmd-R) in Xcode.

Free personal signing gives you a 7-day build — the app stops launching after a week until you re-run it from Xcode. If you pay for the Apple Developer Program ($99/yr) the cert lasts a year and you also unlock TestFlight.

## How to add a new list later

1. Generate a JSON from your CSV (same schema as the existing JSONs) and add it to the Xcode project's `Resources/` group (Copy if needed + target membership checked).
2. Open `Models/AcronymList.swift` and add one entry:
   ```swift
   .init(id: "secplus",
         displayName: "CompTIA Security+ (SY0-701)",
         resourceName: "SecurityPlus"),
   ```
   `id` is a stable short string used in `UserDefaults` — don't reuse an existing one. `resourceName` is the JSON filename without `.json`.
3. Build & run; the new list shows up as a toggle in Settings.

## Feature map (Python → iOS)

| Python (Tk)                        | iOS (SwiftUI)                                       |
|------------------------------------|-----------------------------------------------------|
| Randomize on reload                | Same, via `Array.shuffle()`                         |
| Toggle reveal (space / return)     | Tap the card, or tap Reveal/Hide                    |
| Next (→ / ↓)                       | Right-hand chevron, or swipe left on the card       |
| Previous (← / ↑)                   | Left-hand chevron, or swipe right on the card       |
| Mark correct/incorrect (esc)       | Correct/Incorrect pill buttons; long-press flips    |
| Browse → Wikipedia                 | In-app `SFSafariViewController`; extra links via Safari |
| Score: Correct / Incorrect         | Header row                                          |
| Review mode                        | Toggle in Settings                                  |
| Length filter                      | Picker in Settings                                  |
| Multiple CSV files                 | Toggles in Settings (backed by JSON)                |
| Strict mode                        | Toggle in Settings                                  |
| Duplicate-acronym merging          | Same algorithm, case-insensitive                    |
| Manual entry mode (type an acronym)| Magnifying-glass button → search sheet → tap to jump |

## Troubleshooting

- **App launches with "No acronyms loaded."** → Most likely the JSON files didn't get added to the app target. Select each `.json` in the Project Navigator and confirm **Target Membership** in the File Inspector.
- **"Signing for 'CompTIAAcronymTester' requires a development team."** → In Signing & Capabilities pick your personal team, and change the bundle ID to something unique.
- **"Could not launch – operation couldn't be completed. (OSStatus error -402620395)"** or similar on install → Developer Mode isn't on, or you haven't trusted your Apple ID under VPN & Device Management.
- **Acronyms show up in alphabetical clumps instead of shuffled** → That'd be a bug. The code shuffles after merging duplicates. Nothing in Settings disables shuffle.
