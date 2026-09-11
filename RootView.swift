import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.loading {
                ProgressView("NEXXT")
            } else if app.session == nil {
                AuthView()
            } else if app.profile == nil {
                ProfileLoadingView()
            } else {
                MainView()
            }
        }
    }
}

struct ProfileLoadingView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.blue)
            Text("NEXXT")
                .font(.title.bold())
            if app.profileLoading {
                ProgressView()
                Text("Загрузка профиля…")
                    .foregroundStyle(Color.secondary)
            } else {
                Text(app.startupError.isEmpty ? "Не удалось загрузить профиль" : app.startupError)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary)
                Button("Повторить") {
                    Task { await app.refreshSessionAndProfile() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Выйти", role: .destructive) { app.logout() }
        }
        .padding(28)
    }
}
