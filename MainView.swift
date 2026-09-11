import UIKit
import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            ChatsView().tabItem { Label("Чаты", systemImage: "message.fill") }
            FriendsView().tabItem { Label("Друзья", systemImage: "person.2.fill") }
            ChannelsView().tabItem { Label("Каналы", systemImage: "megaphone.fill") }
            BluetoothScreen().tabItem { Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right") }
            SettingsScreen().tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
    }
}

struct ChatsView: View {
    @EnvironmentObject var app: AppState
    @State private var friends: [UserProfile] = []
    @State private var errorText = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = app.profile {
                    Section("Мой профиль") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName).font(.headline)
                            Text("@\(profile.nickname)").font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }

                Section("Чаты") {
                    if loading {
                        HStack { ProgressView(); Text("Загрузка…") }
                    } else if friends.isEmpty {
                        EmptyState(icon: "person.2", title: "Друзей пока нет", subtitle: "Добавьте человека во вкладке «Друзья», и он появится здесь.")
                            .frame(minHeight: 180)
                    } else {
                        ForEach(friends) { user in
                            NavigationLink { ChatView(user: user) } label: { UserRow(user: user) }
                        }
                    }
                }

                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundStyle(Color.red) }
                }
            }
            .navigationTitle("Чаты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await loadFriends() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await loadFriends() }
    }

    @MainActor private func loadFriends() async {
        guard let session = try? await app.validSession() else { return }
        loading = true
        errorText = ""
        defer { loading = false }
        do { friends = try await app.firebase.friends(session: session) }
        catch { errorText = error.localizedDescription }
    }
}

struct UserRow: View {
    let user: UserProfile
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Text(String(user.displayName.first ?? "?").uppercased()).font(.headline))
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                Text("@\(user.nickname)").font(.caption).foregroundStyle(Color.secondary)
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 44))
            Text(title).font(.title3.bold())
            Text(subtitle).foregroundStyle(Color.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var nick = ""
    @State private var message = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                if let p = app.profile {
                    Section("Профиль") {
                        NEXXTTextField(text: $name, placeholder: "Имя", autoFocus: true)
                            .frame(height: 50)
                        NEXXTTextField(text: $nick, placeholder: "Ник")
                            .frame(height: 50)
                        Button(saving ? "Сохранение…" : "Сохранить") { Task { await save() } }.disabled(saving)
                        if !message.isEmpty { Text(message).foregroundStyle(Color.secondary) }
                    }
                    .onAppear { name = p.displayName; nick = p.nickname }
                }
                Section { Button("Выйти", role: .destructive) { app.logout() } }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    @MainActor private func save() async {
        guard let session = try? await app.validSession() else { return }
        saving = true; defer { saving = false }
        do {
            try await app.firebase.updateProfile(session: session, displayName: name, nickname: nick)
            try await app.loadProfile()
            message = "Сохранено"
        } catch { message = error.localizedDescription }
    }
}
