import UIKit
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    let user: UserProfile

    @State private var messages: [NMessage] = []
    @State private var text = ""
    @State private var errorText = ""
    @State private var timer: Timer?

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    errorView
                    composer
                }
                .background(.regularMaterial)
            }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
            startPolling()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages.indices, id: \.self) { index in
                        let item = messages[index]
                        let previousID = index > 0 ? messages[index - 1].senderId : nil
                        let nextID = index + 1 < messages.count ? messages[index + 1].senderId : nil
                        let sameBefore = previousID == item.senderId
                        let sameAfter = nextID == item.senderId

                        MessageRow(
                            message: item,
                            isMine: item.senderId == app.session?.localId,
                            showTime: !sameAfter,
                            groupedBefore: sameBefore
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToLast(proxy)
            }
            .task {
                scrollToLast(proxy)
            }
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if !errorText.isEmpty {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(Color.red)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            NEXXTTextEditor(text: $text, placeholder: "Сообщение…", minHeight: 52, maxHeight: 120, autoFocus: true)
                .frame(height: 52)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard let session = try? await app.validSession() else { return }
        do {
            let loaded = try await app.firebase.messages(session: session, other: user.uid)
            messages = loaded.sorted { $0.date < $1.date }
            errorText = ""
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard let session = try? await app.validSession() else { return }

        text = ""
        do {
            try await app.firebase.sendMessage(
                session: session,
                receiver: user.uid,
                text: value
            )
            errorText = ""
            await reload()
        } catch {
            text = value
            errorText = error.localizedDescription
        }
    }
}

private struct MessageRow: View {
    let message: NMessage
    let isMine: Bool
    let showTime: Bool
    let groupedBefore: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: groupedBefore ? 12 : 18))

                if showTime {
                    Text(message.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }

            if !isMine { Spacer(minLength: 40) }
        }
        .padding(.top, groupedBefore ? 0 : 5)
    }

    private var bubbleColor: Color {
        isMine ? Color.blue.opacity(0.85) : Color.secondary.opacity(0.22)
    }
}
