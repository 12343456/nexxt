import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var app: AppState
    @State private var nickname = ""
    @State private var friends: [UserProfile] = []
    @State private var incoming: [FriendRequest] = []
    @State private var outgoing: [FriendRequest] = []
    @State private var errorText = ""
    @State private var infoText = ""
    @State private var busy = false
    @State private var requestBusyIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section("Добавить друга") {
                    HStack {
                        NEXXTTextField(
                            text: $nickname,
                            placeholder: "@nickname",
                            keyboardType: .default,
                            returnKeyType: .send,
                            autoFocus: true
                        )
                        Button("Отправить") {
                            Task { await sendByNickname() }
                        }
                        .disabled(busy || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !infoText.isEmpty { Text(infoText).font(.caption).foregroundStyle(Color.secondary) }
                }

                if !incoming.isEmpty {
                    Section("Входящие заявки") {
                        ForEach(incoming) { request in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.senderNickname.isEmpty ? "Пользователь" : "@\(request.senderNickname)")
                                        .font(.headline)
                                    Text("Хочет добавить вас в друзья")
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await accept(request) }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                .disabled(requestBusyIDs.contains(request.id))
                                Button {
                                    Task { await reject(request) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .foregroundStyle(Color.red)
                                .disabled(requestBusyIDs.contains(request.id))
                            }
                        }
                    }
                }

                Section("Друзья") {
                    if friends.isEmpty {
                        Text("Друзей пока нет")
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(friends) { user in
                            NavigationLink {
                                ChatView(user: user)
                            } label: {
                                UserRow(user: user)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await removeFriend(user) }
                                } label: {
                                    Label("Удалить", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }

                if !outgoing.isEmpty {
                    Section("Отправленные заявки") {
                        ForEach(outgoing) { request in
                            Text("Заявка отправлена")
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                if !errorText.isEmpty {
                    Section { Text(errorText).foregroundStyle(Color.red) }
                }
            }
            .navigationTitle("Друзья")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await reload() }
    }

    @MainActor
    private func reload() async {
        guard let session = try? await app.validSession() else { return }
        errorText = ""
        do {
            friends = try await app.firebase.friends(session: session)
            incoming = try await app.firebase.friendRequests(session: session, incoming: true)
            outgoing = try await app.firebase.friendRequests(session: session, incoming: false)
            try? await app.loadProfile()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func sendByNickname() async {
        let clean = nickname.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        guard !clean.isEmpty, let session = try? await app.validSession() else { return }
        busy = true
        defer { busy = false }
        errorText = ""
        infoText = ""
        do {
            guard let user = try await app.firebase.userByNickname(session: session, nickname: clean) else {
                throw FirebaseError.message("Пользователь с таким ником не найден")
            }
            try await app.firebase.sendFriendRequest(session: session, receiverId: user.uid)
            nickname = ""
            infoText = "Приглашение отправлено пользователю @\(user.nickname)"
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func accept(_ request: FriendRequest) async {
        requestBusyIDs.insert(request.id)
        defer { requestBusyIDs.remove(request.id) }
        guard let session = try? await app.validSession() else { return }
        do {
            try await app.firebase.acceptFriendRequest(session: session, request: request)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func reject(_ request: FriendRequest) async {
        requestBusyIDs.insert(request.id)
        defer { requestBusyIDs.remove(request.id) }
        guard let session = try? await app.validSession() else { return }
        do {
            try await app.firebase.rejectFriendRequest(session: session, request: request)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func removeFriend(_ user: UserProfile) async {
        guard let session = try? await app.validSession() else { return }
        do {
            try await app.firebase.removeFriend(session: session, otherId: user.uid)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
