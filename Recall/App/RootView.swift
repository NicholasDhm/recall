import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Gravar", systemImage: "mic.fill") {
                RecordView()
            }
            Tab("Biblioteca", systemImage: "waveform") {
                LibraryView()
            }
            Tab("Insights", systemImage: "chart.bar.fill") {
                InsightsView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootView()
}
