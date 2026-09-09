# Recall

An iPhone app that records audio, transcribes it on the device, summarises the transcript
with Apple's on-device model, and charts what you have been recording. There is no server,
no account and no network call: every recording, transcript and summary stays on the phone.

Four tabs — **Gravar** (record with a live transcript), **Biblioteca** (search, import,
play back, share), **Insights** (charts over your recordings) and **Ajustes** (language,
model status, storage). The interface is in Brazilian Portuguese; the code is in English.

## Architecture

A single SwiftUI app target with no third-party dependencies. `Recording` and
`TranscriptSegment` are SwiftData models in a local `ModelContainer` (CloudKit
deliberately off); audio is AAC `.m4a` — mono, 32 kbps, 16 kHz — in
`Application Support/Recordings/`, referenced by file name only. `AudioRecorder` taps
`AVAudioEngine` and fans each converted buffer out to three consumers: the `AVAudioFile`
being written, the level meter, and `LiveTranscriber`, which feeds `SpeechAnalyzer` for
the live transcript. `RecordingPipeline` then drives `recorded → transcribed → ready`
one recording at a time, re-queuing anything left mid-step when the app launches, and
`TranscriptAnalyzer` produces the summary, tags and action items through
`FoundationModels` with `@Generable` output, chunking long transcripts and consolidating
the parts. Insights aggregations are pure functions over plain value types, which is what
makes them straightforward to test.

## Build and test

```
xcodegen generate      # only needed after changing project.yml or adding files

xcodebuild -project Recall.xcodeproj -scheme Recall \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build test | tail -30
```

Compile for a real device without signing, which catches what the simulator hides:

```
xcodebuild -project Recall.xcodeproj -scheme Recall \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO | tail -20
```

Requires Xcode 26 with the iOS 26 SDK. `xcodegen` comes from `brew install xcodegen`;
the generated `Recall.xcodeproj` is committed, so you can open the project without it.

## Installing on your iPhone with a free Apple ID

A free account works. It gives you a *Personal Team*, which is enough for this app —
nothing here needs iCloud, push notifications, App Groups or Sign in with Apple.

1. **Xcode → Settings → Accounts**, add your Apple ID. It appears as a Personal Team.
2. Copy the signing config and fill in your team:
   ```
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Set `DEVELOPMENT_TEAM` to your Team ID — it is the 10-character string shown in
   **Signing & Capabilities** once the team is selected. `Config/Local.xcconfig` is
   git-ignored, so your team ID never lands in the repository.
3. On the iPhone: **Ajustes → Privacidade e Segurança → Modo Desenvolvedor**, turn it on
   and restart the phone.
4. Connect by cable, trust the computer, pick the iPhone as the destination in Xcode and
   press Run.
5. On the iPhone: **Ajustes → Geral → VPN e Gerenciamento de Dispositivo**, and trust
   your developer certificate.
6. Personal Team limits: the provisioning profile expires after **7 days** (just run from
   Xcode again to reinstall), at most **3** side-loaded apps at a time, and no iCloud.

## What the simulator can and cannot show

- **Transcription is device-only.** In the iOS 26.5 simulator `SpeechTranscriber.isAvailable`
  is `false` and `supportedLocales` is empty, so **Ajustes** reports no transcription
  language and the pipeline marks recordings as failed with a readable reason. On an
  iPhone running iOS 26 the language appears, the model downloads with progress, and the
  live transcript fills in while you speak.
- **Analysis does work in the simulator.** `SystemLanguageModel.default.availability`
  reports `.available` there, and the summary, tags and action items are generated for
  real — `AnalyzerIntegrationTests` exercises the model end to end, including the
  multi-chunk consolidation path. On a device without Apple Intelligence the pipeline
  still reaches `.ready` and the analysis card explains why there is no summary.
- **Recording works in the simulator**, using the Mac's microphone.
  `RecordingPipelineTests` records real audio, plays it back and deletes it.

To check transcription on your phone: install as above, open **Ajustes** and confirm the
speech model shows *Baixado* (download it there if not), then record yourself speaking
Portuguese on the **Gravar** tab — the text appears as you talk.

## Repository layout

```
Recall/App          app entry point, tab shell, navigation
Recall/Models       SwiftData models and the container
Recall/Services     recording, transcription, analysis, insights, export
Recall/Views        one file per screen
Recall/Resources    Info.plist, assets, String Catalog, stopword list
RecallTests         unit tests plus the two on-device integration suites
Scripts             app icon generator
docs/screenshots    one screenshot per tab, plus the recording and detail states
```
