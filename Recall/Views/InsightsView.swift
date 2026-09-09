import SwiftUI

struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Em breve", systemImage: "hammer")
                .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
