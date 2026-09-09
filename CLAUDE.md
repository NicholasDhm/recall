# Recall

iPhone app that records audio, transcribes it on-device, analyses the transcript with
Apple's on-device model and charts the result. Everything runs and stays on the phone.

## Build and test

Generate the Xcode project after any change to `project.yml` or after adding/removing files:

```
xcodegen generate
```

Build and test on the simulator:

```
xcodebuild -project Recall.xcodeproj -scheme Recall \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test | tail -30
```

Verify it also compiles for a real device (catches errors the simulator hides):

```
xcodebuild -project Recall.xcodeproj -scheme Recall \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO | tail -20
```

Regenerate the app icon:

```
swift Scripts/make-icon.swift
```

## Hard constraints

- **No third-party dependencies.** Apple frameworks only. No SPM package that is not Apple's.
- **No network.** The app makes no HTTP calls. No backend, no API key, no analytics.
  If a feature needs the network, it is out of scope.
- **Free Apple account (Personal Team).** No iCloud/CloudKit, no Push Notifications, no
  App Groups, no Sign in with Apple — do not add those capabilities or entitlements.
  `SwiftData` runs with `cloudKitDatabase: .none`. Keep the `ModelContainer` shaped so
  enabling CloudKit later is a one-line change, but leave it off.
- **iPhone only, iOS 26.0 minimum.** Portrait only.
- Bundle identifier is `com.nickdhm.recall`. `DEVELOPMENT_TEAM` comes from
  `Config/Local.xcconfig`, which is git-ignored; `Config/Local.xcconfig.example` is committed.
- The generated `Recall.xcodeproj` is committed so the project opens without running anything.

## Conventions

- UI text in **Brazilian Portuguese**. Code, identifiers, comments and commits in **English**.
- All user-facing strings go through the String Catalog (`Localizable.xcstrings`). No
  hard-coded strings scattered in views.
- Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`). Keep it warning-free.
- Simplicity first: few screens, few files, no preventive abstraction. No generic "Manager",
  "Coordinator" or "Repository". One service per real responsibility: recording,
  transcription, analysis, storage.
- Comments only for constraints the code cannot express. Never narrate the next line.
- No colour on numbers unless the colour matches a visual element in an adjacent chart.
- Basic accessibility: labels on icon-only buttons, Dynamic Type in lists and the transcript.

## Verify APIs before using them

`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory` and `FoundationModels` are iOS 26
frameworks. Read the real interfaces in the installed SDK before coding against them:

```
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
sed -n '1,200p' "$SDK/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-ios.swiftinterface"
sed -n '1,200p' "$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface"
```

If a symbol does not exist, adapt. Do not invent one.

## Working rules

- One commit per phase, imperative English subject, short body. Build must be green and
  tests passing before committing.
- **Never** add `Co-Authored-By` or `Claude-Session` trailers to commits.
- Never claim something works without running the build and the tests, and reporting the
  real output. Report failures verbatim.
- If delegating: `haiku` for mechanical work, `sonnet` for well-specified implementation.
  Never `fable`.

## Audio and storage facts

- Recordings are AAC `.m4a`, mono, 32 kbps, 16 kHz. The format is defined in one place only.
- Audio files live in `Application Support/Recordings/`, never in `Documents`.
- Only relative file names are stored in SwiftData; absolute URLs are never persisted.
- Deleting a recording deletes its audio file.
