import SwiftUI

struct RecordView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Em breve", systemImage: "hammer")
                .navigationTitle("Gravar")
        }
    }
}

#Preview {
    RecordView()
}
