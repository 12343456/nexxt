import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum FirebaseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

final class FirebaseREST {
    private let apiKey = "AIzaSyDoXoYHS5PIB1TnlqQQce7aKE8LFdYg6i0"
    private let project = "messenger-nexxt"
    private let http: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
    private var base: String { "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents" }

    func signIn(email: String, password: String) async throws -> FirebaseSession {
        try await auth(path: "accounts:signInWithPassword", email: email, password: password)
    }

    func signUp(email: String, password: String) async throws -> FirebaseSession {
        try await auth(path: "accounts:signUp", email: email, password: password)
    }

    private func auth(path: String, email: String, password: String) async throws -> FirebaseSession {
        var request = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/\(path)?key=\(apiKey)")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "returnSecureToken": true])
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirebaseError.message("Нет ответа Firebase") }
        guard (200..<300).contains(http.statusCode) else { throw FirebaseError.message(Self.firebaseMessage(data, fallback: "Ошибка Firebase Authentication")) }
        let value = try JSONDecoder().decode(AuthResponse.self, from: data)
        return FirebaseSession(localId: value.localId, idToken: value.idToken, refreshToken: value.refreshToken, email: value.email, expiresAt: Date().addingTimeInterval(TimeInterval(Int(value.expiresIn) ?? 3600) - 60))
    }

    private struct AuthResponse: Decodable {
        let localId: String
        let idToken: String
        let refreshToken: String
        let expiresIn: String
        let email: String
    }

    func refresh(_ session: FirebaseSession) async throws -> FirebaseSession {
        var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(session.refreshToken)".data(using: .utf8)
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw FirebaseError.message(Self.firebaseMessage(data, fallback: "Сессия Firebase истекла")) }
        let value = try JSONDecoder().decode(RefreshResponse.self, from: data)
        return FirebaseSession(localId: value.userId, idToken: value.idToken, refreshToken: value.refreshToken, email: session.email, expiresAt: Date().addingTimeInterval(TimeInterval(Int(value.expiresIn) ?? 3600) - 60))
    }

    private struct RefreshResponse: Decodable {
        let idToken: String
        let refreshToken: String
        let expiresIn: String
        let userId: String
    }

    func ensureFresh(_ session: FirebaseSession) async throws -> FirebaseSession {
        if session.expiresAt > Date() { return session }
        return try await refresh(session)
    }

    func createProfile(session: FirebaseSession, email: String, name: String, nickname: String) async throws {
        let nick = nickname.lowercased().replacingOccurrences(of: "@", with: "")
        if try await getUsername(session: session, nickname: nick) != nil {
            throw FirebaseError.message("Этот ник уже занят")
        }
        var fields: [String: Any] = [:]
        fields["uid"] = stringValue(session.localId)
        fields["email"] = stringValue(email)
        fields["displayName"] = stringValue(name)
        fields["nickname"] = stringValue(nick)
        fields["avatarUrl"] = stringValue("")
        fields["friends"] = emptyArrayValue()
        fields["joinedChannels"] = emptyArrayValue()
        let profileBody: [String: Any] = ["fields": fields]
        _ = try await request(method: "PATCH", url: "\(base)/users/\(session.localId)", token: session.idToken, body: profileBody)

        var usernameFields: [String: Any] = [:]
        usernameFields["uid"] = stringValue(session.localId)
        usernameFields["nickname"] = stringValue(nick)
        let usernameBody: [String: Any] = ["fields": usernameFields]
        _ = try await request(method: "PATCH", url: "\(base)/usernames/\(nick)", token: session.idToken, body: usernameBody)
    }

    func getProfile(session: FirebaseSession) async throws -> UserProfile? {
        let data = try await request(method: "GET", url: "\(base)/users/\(session.localId)", token: session.idToken, body: nil)
        return parseUser(data)
    }

    func users(session: FirebaseSession) async throws -> [UserProfile] {
        let data = try await request(method: "GET", url: "\(base)/users?pageSize=100", token: session.idToken, body: nil)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let docs = root["documents"] as? [[String: Any]] else { return [] }
        return docs.compactMap(parseUserObject).filter { $0.uid != session.localId }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// NEXXT web-compatible friends: the canonical list is users/{uid}.friends.
    /// The website does NOT keep accepted friendRequests; it removes the request
    /// and stores both UIDs in the two users' friends arrays.
    func friends(session: FirebaseSession) async throws -> [UserProfile] {
        guard let me = try await getProfile(session: session) else { return [] }
        let ids = me.friends.filter { $0 != session.localId }
        if ids.isEmpty { return [] }
        var result: [UserProfile] = []
        for uid in ids {
            if let user = try await getUser(session: session, uid: uid) { result.append(user) }
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func getUser(session: FirebaseSession, uid: String) async throws -> UserProfile? {
        let safe = uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid
        do {
            let data = try await request(method: "GET", url: "\(base)/users/\(safe)", token: session.idToken, body: nil)
            return parseUser(data)
        } catch let error as FirebaseError {
            if error.localizedDescription.contains("NOT_FOUND") || error.localizedDescription.contains("not found") { return nil }
            throw error
        }
    }

    func userByNickname(session: FirebaseSession, nickname: String) async throws -> UserProfile? {
        guard let uid = try await getUsername(session: session, nickname: nickname) else { return nil }
        return try await getUser(session: session, uid: uid)
    }

    func getUsername(session: FirebaseSession, nickname: String) async throws -> String? {
        let encoded = nickname.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nickname
        let data = try? await request(method: "GET", url: "\(base)/usernames/\(encoded)", token: session.idToken, body: nil)
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let fields = object["fields"] as? [String: Any] else { return nil }
        return string(fields, "uid")
    }

    func sendMessage(session: FirebaseSession, receiver: String, text: String) async throws {
        var fields: [String: Any] = [:]
        fields["senderId"] = stringValue(session.localId)
        fields["receiverId"] = stringValue(receiver)
        fields["text"] = stringValue(text)
        fields["timestamp"] = timestampValue(Date())
        fields["isRead"] = boolValue(false)
        let body: [String: Any] = ["fields": fields]
        _ = try await request(method: "POST", url: "\(base)/messages", token: session.idToken, body: body)
    }

    func messages(session: FirebaseSession, other: String) async throws -> [NMessage] {
        async let outgoing = queryMessages(session: session, sender: session.localId, receiver: other)
        async let incoming = queryMessages(session: session, sender: other, receiver: session.localId)
        let first = try await outgoing
        let second = try await incoming
        return (first + second).sorted { $0.date < $1.date }
    }

    private func queryMessages(session: FirebaseSession, sender: String, receiver: String) async throws -> [NMessage] {
        let senderFilter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": "senderId"],
                "op": "EQUAL",
                "value": stringValue(sender)
            ]
        ]
        let receiverFilter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": "receiverId"],
                "op": "EQUAL",
                "value": stringValue(receiver)
            ]
        ]
        let composite: [String: Any] = [
            "op": "AND",
            "filters": [senderFilter, receiverFilter]
        ]
        let whereValue: [String: Any] = ["compositeFilter": composite]
        let structured: [String: Any] = [
            "from": [["collectionId": "messages"]],
            "where": whereValue
        ]
        let query: [String: Any] = ["structuredQuery": structured]
        let data = try await request(method: "POST", url: "\(base):runQuery", token: session.idToken, body: query)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row -> NMessage? in
            guard let doc = row["document"] as? [String: Any],
                  let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any] else { return nil }
            let id = name.split(separator: "/").last.map(String.init) ?? UUID().uuidString
            let timestamp = string(fields, "timestamp")
            let date = ISO8601DateFormatter().date(from: timestamp) ?? Date()
            return NMessage(id: id, senderId: string(fields, "senderId"), receiverId: string(fields, "receiverId"), text: string(fields, "text"), date: date)
        }
    }

    func channels(session: FirebaseSession) async throws -> [NChannel] {
        let data = try await request(method: "GET", url: "\(base)/channels?pageSize=100", token: session.idToken, body: nil)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let docs = root["documents"] as? [[String: Any]] else { return [] }
        return docs.compactMap(parseChannel).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns only channels the user owns or is subscribed to.
    /// This deliberately does NOT download the entire channels collection.
    func myChannels(session: FirebaseSession) async throws -> [NChannel] {
        async let subscribed = queryChannels(session: session, fieldPath: "members", op: "ARRAY_CONTAINS", value: stringValue(session.localId))
        async let owned = queryChannels(session: session, fieldPath: "ownerId", op: "EQUAL", value: stringValue(session.localId))
        let a = try await subscribed
        let b = try await owned
        var unique: [String: NChannel] = [:]
        for channel in a + b { unique[channel.id] = channel }
        return Array(unique.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func queryChannels(session: FirebaseSession, fieldPath: String, op: String, value: [String: Any]) async throws -> [NChannel] {
        let filter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": fieldPath],
                "op": op,
                "value": value
            ]
        ]
        let structured: [String: Any] = [
            "from": [["collectionId": "channels"]],
            "where": filter
        ]
        let query: [String: Any] = ["structuredQuery": structured]
        let data = try await request(method: "POST", url: "\(base):runQuery", token: session.idToken, body: query)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let document = row["document"] as? [String: Any] else { return nil }
            return parseChannel(document)
        }
    }

    func createChannel(session: FirebaseSession, name: String, username: String, description: String) async throws -> NChannel {
        let nick = username.lowercased().replacingOccurrences(of: "@", with: "")
        if try await getChannelUsername(session: session, username: nick) != nil {
            throw FirebaseError.message("Этот username канала уже занят")
        }
        let id = UUID().uuidString
        var fields: [String: Any] = [:]
        fields["name"] = stringValue(name)
        fields["username"] = stringValue(nick)
        fields["description"] = stringValue(description)
        fields["ownerId"] = stringValue(session.localId)
        fields["type"] = stringValue("channel")
        fields["members"] = arrayValue([session.localId])
        fields["subscriberCount"] = integerValue(0)
        fields["avatarUrl"] = stringValue("")
        let body: [String: Any] = ["fields": fields]
        _ = try await request(method: "PATCH", url: "\(base)/channels/\(id)", token: session.idToken, body: body)

        var usernameFields: [String: Any] = [:]
        usernameFields["channelId"] = stringValue(id)
        usernameFields["ownerId"] = stringValue(session.localId)
        let usernameBody: [String: Any] = ["fields": usernameFields]
        _ = try await request(method: "PATCH", url: "\(base)/channelUsernames/\(nick)", token: session.idToken, body: usernameBody)
        return NChannel(id: id, name: name, username: nick, description: description, ownerId: session.localId, members: [session.localId], subscriberCount: 0, avatarUrl: nil)
    }

    func getChannelUsername(session: FirebaseSession, username: String) async throws -> String? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let data = try? await request(method: "GET", url: "\(base)/channelUsernames/\(encoded)", token: session.idToken, body: nil)
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let fields = object["fields"] as? [String: Any] else { return nil }
        return string(fields, "channelId")
    }

    func joinChannel(session: FirebaseSession, channel: NChannel) async throws {
        var updated = channel.members
        if !updated.contains(session.localId) { updated.append(session.localId) }
        let count = max(0, updated.filter { $0 != channel.ownerId }.count)
        try await patchChannel(session: session, channel: channel, members: updated, subscriberCount: count)
    }

    func leaveChannel(session: FirebaseSession, channel: NChannel) async throws {
        let updated = channel.members.filter { $0 != session.localId || $0 == channel.ownerId }
        let count = max(0, updated.filter { $0 != channel.ownerId }.count)
        try await patchChannel(session: session, channel: channel, members: updated, subscriberCount: count)
    }

    private func patchChannel(session: FirebaseSession, channel: NChannel, members: [String], subscriberCount: Int) async throws {
        var fields: [String: Any] = [:]
        fields["members"] = arrayValue(members)
        fields["subscriberCount"] = integerValue(subscriberCount)
        let body: [String: Any] = ["fields": fields]
        let url = "\(base)/channels/\(channel.id)?updateMask.fieldPaths=members&updateMask.fieldPaths=subscriberCount"
        _ = try await request(method: "PATCH", url: url, token: session.idToken, body: body)
    }

    func channelMessages(session: FirebaseSession, channelId: String) async throws -> [ChannelMessage] {
        let query: [String: Any] = ["structuredQuery": ["from": [["collectionId": "channelMessages"]], "where": ["fieldFilter": ["field": ["fieldPath": "channelId"], "op": "EQUAL", "value": ["stringValue": channelId]]]]]
        let data = try await request(method: "POST", url: "\(base):runQuery", token: session.idToken, body: query)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String, let fields = doc["fields"] as? [String: Any] else { return nil }
            let date = ISO8601DateFormatter().date(from: string(fields, "timestamp")) ?? Date()
            return ChannelMessage(id: name.split(separator: "/").last.map(String.init) ?? UUID().uuidString, channelId: string(fields, "channelId"), senderId: string(fields, "senderId"), text: string(fields, "text"), date: date)
        }.sorted { $0.date < $1.date }
    }

    func sendChannelMessage(session: FirebaseSession, channelId: String, text: String) async throws {
        var fields: [String: Any] = [:]
        fields["channelId"] = stringValue(channelId)
        fields["senderId"] = stringValue(session.localId)
        fields["text"] = stringValue(text)
        fields["timestamp"] = timestampValue(Date())
        let body: [String: Any] = ["fields": fields]
        _ = try await request(method: "POST", url: "\(base)/channelMessages", token: session.idToken, body: body)
    }

    func friendRequests(session: FirebaseSession, incoming: Bool, status: String? = "pending") async throws -> [FriendRequest] {
        let field = incoming ? "toUid" : "fromUid"
        let filter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": field],
                "op": "EQUAL",
                "value": stringValue(session.localId)
            ]
        ]
        let structured: [String: Any] = [
            "from": [["collectionId": "friendRequests"]],
            "where": filter
        ]
        let query: [String: Any] = ["structuredQuery": structured]
        let data = try await request(method: "POST", url: "\(base):runQuery", token: session.idToken, body: query)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var result = rows.compactMap(parseFriendRequest)
        if let status { result = result.filter { $0.status == status } }
        return result.sorted { $0.date > $1.date }
    }

    func sendFriendRequest(session: FirebaseSession, receiverId: String) async throws {
        guard receiverId != session.localId else { throw FirebaseError.message("Нельзя добавить самого себя") }
        guard let target = try await getUser(session: session, uid: receiverId) else { throw FirebaseError.message("Пользователь не найден") }
        if let me = try await getProfile(session: session), me.friends.contains(receiverId) { throw FirebaseError.message("Этот пользователь уже у вас в друзьях") }

        let reverseID = "\(receiverId)_\(session.localId)"
        if let reverse = try await friendRequestByID(session: session, id: reverseID), reverse.status == "pending" {
            try await acceptFriendRequest(session: session, request: reverse)
            return
        }
        let id = "\(session.localId)_\(receiverId)"
        if let existing = try await friendRequestByID(session: session, id: id), existing.status == "pending" {
            throw FirebaseError.message("Заявка уже отправлена")
        }
        guard let me = try await getProfile(session: session) else { throw FirebaseError.message("Профиль не найден") }
        var fields: [String: Any] = [:]
        fields["fromUid"] = stringValue(session.localId)
        fields["toUid"] = stringValue(receiverId)
        fields["fromDisplayName"] = stringValue(me.displayName)
        fields["fromNickname"] = stringValue(me.nickname)
        fields["toNickname"] = stringValue(target.nickname)
        fields["status"] = stringValue("pending")
        fields["createdAt"] = timestampValue(Date())
        let body: [String: Any] = ["fields": fields]
        _ = try await request(method: "PATCH", url: "\(base)/friendRequests/\(id)", token: session.idToken, body: body)
    }

    func acceptFriendRequest(session: FirebaseSession, request friendRequest: FriendRequest) async throws {
        guard friendRequest.receiverId == session.localId else { throw FirebaseError.message("Нет доступа") }
        guard friendRequest.status == "pending" else { throw FirebaseError.message("Заявка уже обработана") }
        var me = try await getProfile(session: session)?.friends ?? []
        var other = try await getUser(session: session, uid: friendRequest.senderId)?.friends ?? []
        if !me.contains(friendRequest.senderId) { me.append(friendRequest.senderId) }
        if !other.contains(session.localId) { other.append(session.localId) }
        try await updateUserFriends(session: session, uid: session.localId, friends: me)
        try await updateUserFriends(session: session, uid: friendRequest.senderId, friends: other)
        try await deleteFriendRequest(session: session, id: friendRequest.id)
    }

    func rejectFriendRequest(session: FirebaseSession, request friendRequest: FriendRequest) async throws {
        guard friendRequest.receiverId == session.localId else { throw FirebaseError.message("Нет доступа") }
        try await deleteFriendRequest(session: session, id: friendRequest.id)
    }

    func removeFriend(session: FirebaseSession, otherId: String) async throws {
        guard var me = try await getProfile(session: session)?.friends else { throw FirebaseError.message("Профиль не найден") }
        guard var other = try await getUser(session: session, uid: otherId)?.friends else { throw FirebaseError.message("Пользователь не найден") }
        guard me.contains(otherId) else { throw FirebaseError.message("Дружба не найдена") }
        me.removeAll { $0 == otherId }
        other.removeAll { $0 == session.localId }
        try await updateUserFriends(session: session, uid: session.localId, friends: me)
        try await updateUserFriends(session: session, uid: otherId, friends: other)
    }

    private func updateUserFriends(session: FirebaseSession, uid: String, friends: [String]) async throws {
        var fields: [String: Any] = [:]
        fields["friends"] = arrayValue(friends)
        let body: [String: Any] = ["fields": fields]
        let safe = uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid
        _ = try await request(method: "PATCH", url: "\(base)/users/\(safe)?updateMask.fieldPaths=friends", token: session.idToken, body: body)
    }

    private func deleteFriendRequest(session: FirebaseSession, id: String) async throws {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await request(method: "DELETE", url: "\(base)/friendRequests/\(safe)", token: session.idToken, body: nil)
    }

    private func friendRequestByID(session: FirebaseSession, id: String) async throws -> FriendRequest? {
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        do {
            let data = try await request(method: "GET", url: "\(base)/friendRequests/\(safeID)", token: session.idToken, body: nil)
            return parseFriendRequest(try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:])
        } catch let error as FirebaseError {
            if error.localizedDescription.contains("NOT_FOUND") || error.localizedDescription.contains("not found") { return nil }
            throw error
        }
    }

    private func parseFriendRequest(_ d: [String: Any]) -> FriendRequest? {
        guard let f = d["fields"] as? [String: Any], let name = d["name"] as? String else { return nil }
        let id = name.split(separator: "/").last.map(String.init) ?? UUID().uuidString
        let sender = string(f, "fromUid").isEmpty ? string(f, "senderId") : string(f, "fromUid")
        let receiver = string(f, "toUid").isEmpty ? string(f, "receiverId") : string(f, "toUid")
        let status = string(f, "status")
        let dateString = string(f, "createdAt").isEmpty ? string(f, "timestamp") : string(f, "createdAt")
        let date = ISO8601DateFormatter().date(from: dateString) ?? Date()
        guard !sender.isEmpty, !receiver.isEmpty else { return nil }
        return FriendRequest(id: id, senderId: sender, receiverId: receiver, status: status, date: date, senderNickname: string(f, "fromNickname"))
    }

    private func parseUser(_ data: Data) -> UserProfile? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parseUserObject(object)
    }

    private func parseUserObject(_ d: [String: Any]) -> UserProfile? {
        guard let f = d["fields"] as? [String: Any] else { return nil }
        let uid = string(f, "uid").isEmpty ? ((d["name"] as? String)?.split(separator: "/").last.map(String.init) ?? "") : string(f, "uid")
        guard !uid.isEmpty else { return nil }
        return UserProfile(uid: uid, email: string(f, "email"), displayName: string(f, "displayName").isEmpty ? string(f, "nickname") : string(f, "displayName"), nickname: string(f, "nickname"), avatarUrl: string(f, "avatarUrl"), friends: array(f, "friends"), joinedChannels: array(f, "joinedChannels"))
    }

    private func parseChannel(_ d: [String: Any]) -> NChannel? {
        guard let f = d["fields"] as? [String: Any], let name = d["name"] as? String else { return nil }
        let id = name.split(separator: "/").last.map(String.init) ?? UUID().uuidString
        return NChannel(id: id, name: string(f, "name"), username: string(f, "username"), description: string(f, "description"), ownerId: string(f, "ownerId"), members: array(f, "members"), subscriberCount: Int(string(f, "subscriberCount")) ?? 0, avatarUrl: string(f, "avatarUrl"))
    }

    private func string(_ fields: [String: Any], _ key: String) -> String {
        guard let value = fields[key] as? [String: Any] else { return "" }
        if let s = value["stringValue"] as? String { return s }
        if let s = value["timestampValue"] as? String { return s }
        if let s = value["integerValue"] as? String { return s }
        return ""
    }

    private func array(_ fields: [String: Any], _ key: String) -> [String] {
        guard let arrayValue = (fields[key] as? [String: Any])?["arrayValue"] as? [String: Any], let values = arrayValue["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { $0["stringValue"] as? String }
    }

    private func request(method: String, url: String, token: String?, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FirebaseError.message("Нет ответа сервера") }
        guard (200..<300).contains(http.statusCode) else { throw FirebaseError.message(Self.firebaseMessage(data, fallback: "Ошибка Firestore (\(http.statusCode))")) }
        return data
    }

    private static func firebaseMessage(_ data: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = object["error"] as? [String: Any], let message = error["message"] as? String else { return fallback }
        return message.replacingOccurrences(of: "PERMISSION_DENIED", with: "Нет доступа")
    }
    func updateFriends(session: FirebaseSession, friends: [String]) async throws {
        var fields: [String: Any] = [:]
        fields["friends"] = arrayValue(friends)
        let body: [String: Any] = ["fields": fields]
        let url = "\(base)/users/\(session.localId)?updateMask.fieldPaths=friends"
        _ = try await request(method: "PATCH", url: url, token: session.idToken, body: body)
    }

    func updateJoinedChannels(session: FirebaseSession, channels: [String]) async throws {
        var fields: [String: Any] = [:]
        fields["joinedChannels"] = arrayValue(channels)
        let body: [String: Any] = ["fields": fields]
        let url = "\(base)/users/\(session.localId)?updateMask.fieldPaths=joinedChannels"
        _ = try await request(method: "PATCH", url: url, token: session.idToken, body: body)
    }

    func updateProfile(session: FirebaseSession, displayName: String, nickname: String) async throws {
        let nick = nickname.lowercased().replacingOccurrences(of: "@", with: "")
        var fields: [String: Any] = [:]
        fields["displayName"] = stringValue(displayName)
        fields["nickname"] = stringValue(nick)
        let body: [String: Any] = ["fields": fields]
        let url = "\(base)/users/\(session.localId)?updateMask.fieldPaths=displayName&updateMask.fieldPaths=nickname"
        _ = try await request(method: "PATCH", url: url, token: session.idToken, body: body)
    }

    private func stringValue(_ value: String) -> [String: Any] {
        ["stringValue": value]
    }

    private func boolValue(_ value: Bool) -> [String: Any] {
        ["booleanValue": value]
    }

    private func integerValue(_ value: Int) -> [String: Any] {
        ["integerValue": String(value)]
    }

    private func timestampValue(_ date: Date) -> [String: Any] {
        ["timestampValue": ISO8601DateFormatter().string(from: date)]
    }

    private func arrayValue(_ values: [String]) -> [String: Any] {
        let encoded: [[String: Any]] = values.map { stringValue($0) }
        return ["arrayValue": ["values": encoded]]
    }

    private func emptyArrayValue() -> [String: Any] {
        ["arrayValue": ["values": [] as [[String: Any]]]]
    }

}
