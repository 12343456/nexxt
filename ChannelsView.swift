import UIKit
import SwiftUI

struct ChannelsView: View {
    @EnvironmentObject var app: AppState
    @State private var channels: [NChannel] = []
    @State private var search = ""
    @State private var selected: NChannel?
    @State private var showCreate = false
    @State private var errorText = ""

    private var filtered: [NChannel] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.username.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Каналы") {
                    if filtered.isEmpty { Text(errorText.isEmpty ? "Каналов пока нет" : errorText).foregroundStyle(errorText.isEmpty ? Color.secondary : Color.red) }
                    ForEach(filtered) { channel in
                        NavigationLink { ChannelView(channel: channel, onChanged: { Task { await load() } }) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(channel.name).font(.headline)
                                Text("@\(channel.username) · \(channel.subscriberCount) подписчиков").font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Каналы")
            .searchable(text: $search, prompt: "Поиск каналов")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        }
        .task { await load() }
        .sheet(isPresented: $showCreate) { CreateChannelView { Task { await load() } } }
    }

    @MainActor private func load() async {
        guard let session = try? await app.validSession() else { return }
        do { channels = try await app.firebase.myChannels(session: session); errorText = "" }
        catch { errorText = error.localizedDescription }
    }
}

struct CreateChannelView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var name = ""
    @State private var username = ""
    @State private var description = ""
    @State private var errorText = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                NEXXTTextField(text: $name, placeholder: "Название", autoFocus: true)
                    .frame(height: 50)
                NEXXTTextField(text: $username, placeholder: "Username")
                    .frame(height: 50)
                NEXXTTextEditor(text: $description, placeholder: "Описание", minHeight: 70, maxHeight: 120)
                    .frame(minHeight: 70, maxHeight: 120)
                if !errorText.isEmpty { Text(errorText).foregroundStyle(Color.red) }
            }
                .navigationTitle("Новый канал")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Готово") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
 ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(busy ? "…" : "Создать") { Task { await create() } }.disabled(busy) } }
        }
    }
    @MainActor private func create() async {
        guard let session = try? await app.validSession() else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, username.count >= 3 else { errorText = "Укажите название и username от 3 символов"; return }
        busy = true; defer { busy = false }
        do { _ = try await app.firebase.createChannel(session: session, name: name, username: username, description: description); dismiss(); onCreated() }
        catch { errorText = error.localizedDescription }
    }
}

struct ChannelView: View {
    @EnvironmentObject var app: AppState
    let channel: NChannel
    let onChanged: () -> Void
    @State private var messages: [ChannelMessage] = []
    @State private var text = ""
    @State private var errorText = ""
    @State private var timer: Timer?

    private var sessionUserID: String? { app.session?.localId }
    private var isOwner: Bool { channel.ownerId == sessionUserID }
    private var subscribed: Bool { channel.members.contains(sessionUserID ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) { Text(channel.name).font(.title2.bold()); Text("@\(channel.username) · \(channel.subscriberCount) подписчиков").font(.caption).foregroundStyle(Color.secondary); if !channel.description.isEmpty { Text(channel.description).font(.subheadline).foregroundStyle(Color.secondary) } }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) { ForEach(messages) { m in Text(m.text).padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15)).id(m.id) } }.padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading) }.onChange(of: messages) { _, newValue in if let id = newValue.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if !isOwner {
                Button(subscribed ? "Отписаться" : "Подписаться") { Task { await toggleSubscription() } }.buttonStyle(.borderedProminent).padding(8)
            } else {
                HStack {
                    NEXXTTextEditor(text: $text, placeholder: "Новый пост…")
                        .frame(minHeight: 48, maxHeight: 110)
                    Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding()
            }
            if !errorText.isEmpty { Text(errorText).font(.caption).foregroundStyle(Color.red).padding(.bottom, 5) }
        }
        .navigationTitle(channel.name).navigationBarTitleDisplayMode(.inline)
        .task { await reload(); timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await reload() } } }
        .onDisappear { timer?.invalidate() }
    }

    @MainActor private func reload() async { guard let session = try? await app.validSession() else { return }; do { messages = try await app.firebase.channelMessages(session: session, channelId: channel.id) } catch { errorText = error.localizedDescription } }
    @MainActor private func send() async { let value = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty, let session = try? await app.validSession() else { return }; text = ""; do { try await app.firebase.sendChannelMessage(session: session, channelId: channel.id, text: value); await reload() } catch { text = value; errorText = error.localizedDescription } }
    @MainActor private func toggleSubscription() async {
        guard let session = try? await app.validSession() else { return }
        do {
            if subscribed { try await app.firebase.leaveChannel(session: session, channel: channel) } else { try await app.firebase.joinChannel(session: session, channel: channel) }
            var joined = app.profile?.joinedChannels ?? []
            if subscribed { joined.removeAll { $0 == channel.id } } else if !joined.contains(channel.id) { joined.append(channel.id) }
            try await app.firebase.updateJoinedChannels(session: session, channels: joined)
            try await app.loadProfile()
            onChanged()
        } catch { errorText = error.localizedDescription }
    }
}
