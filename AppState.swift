import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var session: FirebaseSession?
    @Published var profile: UserProfile?
    @Published var loading = true
    @Published var profileLoading = false
    @Published var startupError = ""
    let firebase = FirebaseREST()

    init() { restore() }

    func restore() {
        guard let data = UserDefaults.standard.data(forKey: "nexxt.session"),
              let saved = try? JSONDecoder().decode(FirebaseSession.self, from: data) else {
            loading = false
            return
        }

        session = saved
        if let data = UserDefaults.standard.data(forKey: "nexxt.profile"),
           let cached = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = cached
        }

        // The app must render immediately. Firebase refresh happens after the first frame.
        loading = false
        Task { await refreshSessionAndProfile() }
    }

    func login(email: String, password: String) async throws {
        let newSession = try await firebase.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        session = newSession
        saveSession()
        try await loadProfile()
    }

    func register(email: String, password: String, name: String, nickname: String) async throws {
        guard email.contains("@") else { throw FirebaseError.message("Введите корректный email") }
        guard password.count >= 6 else { throw FirebaseError.message("Пароль должен содержать минимум 6 символов") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FirebaseError.message("Введите имя") }
        let cleanNick = nickname.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard cleanNick.count >= 3 else { throw FirebaseError.message("Ник должен содержать минимум 3 символа") }

        let newSession = try await firebase.signUp(email: email, password: password)
        session = newSession
        do {
            try await firebase.createProfile(
                session: newSession,
                email: email,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                nickname: cleanNick
            )
            saveSession()
            try await loadProfile()
        } catch {
            logout()
            throw error
        }
    }

    func refreshSessionAndProfile() async {
        guard let current = session else {
            loading = false
            return
        }
        profileLoading = true
        startupError = ""
        defer { profileLoading = false }

        do {
            let fresh = try await firebase.ensureFresh(current)
            session = fresh
            saveSession()
            try await loadProfile()
        } catch {
            // Keep a cached session/profile so a temporary network failure does not make
            // the application appear frozen or instantly log the user out.
            startupError = error.localizedDescription
        }
    }

    func loadProfile() async throws {
        guard let current = session else {
            profile = nil
            return
        }
        let fresh = try await firebase.ensureFresh(current)
        if fresh.idToken != current.idToken {
            session = fresh
            saveSession()
        }
        guard let loaded = try await firebase.getProfile(session: fresh) else {
            throw FirebaseError.message("Профиль не найден в Firestore")
        }
        profile = loaded
        saveProfile(loaded)
    }

    func validSession() async throws -> FirebaseSession {
        guard let current = session else { throw FirebaseError.message("Вы не вошли в аккаунт") }
        let fresh = try await firebase.ensureFresh(current)
        if fresh.idToken != current.idToken {
            session = fresh
            saveSession()
        }
        return fresh
    }

    func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: "nexxt.session")
    }

    private func saveProfile(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: "nexxt.profile")
    }

    func logout() {
        session = nil
        profile = nil
        loading = false
        profileLoading = false
        startupError = ""
        UserDefaults.standard.removeObject(forKey: "nexxt.session")
        UserDefaults.standard.removeObject(forKey: "nexxt.profile")
    }
}
