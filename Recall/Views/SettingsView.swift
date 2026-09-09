import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Em breve", systemImage: "hammer")
                .navigationTitle("Ajustes")
        }
    }
}

#Preview {
    SettingsView()
}
