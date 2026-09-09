import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Em breve", systemImage: "hammer")
                .navigationTitle("Biblioteca")
        }
    }
}

#Preview {
    LibraryView()
}
