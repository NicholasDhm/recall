import SwiftUI

struct RootView: View {
    @State private var navigation = Navigation()

    init() {
        #if DEBUG
        if let tab = LaunchOptions.initialTab {
            _navigation = State(initialValue: Navigation(selectedTab: tab))
        }
        #endif
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            Tab("Gravar", systemImage: "mic.fill", value: RootTab.record) {
                RecordView()
            }
            Tab("Biblioteca", systemImage: "waveform", value: RootTab.library) {
                LibraryView()
            }
            Tab("Insights", systemImage: "chart.bar.fill", value: RootTab.insights) {
                InsightsView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill", value: RootTab.settings) {
                SettingsView()
            }
        }
        .environment(navigation)
    }
}
