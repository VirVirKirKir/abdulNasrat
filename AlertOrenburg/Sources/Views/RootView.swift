import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .navigationTitle("Тревога · Оренбург")
                .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.orange)
    }
}

#Preview {
    RootView()
}
