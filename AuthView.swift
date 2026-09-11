import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject var app: AppState
    @State private var registration = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var nickname = ""
    @State private var errorText = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 54)).foregroundStyle(Color.blue).padding(.top, 28)
                    Text("NEXXT").font(.system(size: 38, weight: .bold))
                    Text(registration ? "Создайте аккаунт" : "Войдите в аккаунт").foregroundStyle(Color.secondary)

                    if registration {
                        NEXXTTextField(text: $name, placeholder: "Имя", returnKeyType: .next, autoFocus: registration)
                            .frame(height: 50)
                        NEXXTTextField(text: $nickname, placeholder: "Уникальный ник", returnKeyType: .next)
                            .frame(height: 50)
                    }

                    NEXXTTextField(text: $email, placeholder: "Email", keyboardType: .emailAddress, returnKeyType: .next, autoFocus: !registration)
                        .frame(height: 50)
                    NEXXTTextField(text: $password, placeholder: "Пароль", secure: true, returnKeyType: .done) {
                        Task { await submit() }
                    }
                    .frame(height: 50)

                    if !errorText.isEmpty {
                        Text(errorText).font(.footnote).foregroundStyle(Color.red).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button { Task { await submit() } } label: {
                        HStack { if busy { ProgressView().tint(Color.white) }; Text(busy ? "Подождите…" : (registration ? "Создать аккаунт" : "Войти")) }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)

                    Button(registration ? "У меня уже есть аккаунт" : "Создать аккаунт") {
                        registration.toggle(); errorText = ""
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(registration ? "Регистрация" : "Вход")
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

    @MainActor private func submit() async {
        guard !busy else { return }
        errorText = ""; busy = true; defer { busy = false }
        do {
            if registration {
                try await app.register(email: email, password: password, name: name, nickname: nickname)
            } else {
                try await app.login(email: email, password: password)
            }
        } catch { errorText = error.localizedDescription }
    }
}
