import Foundation

struct FirebaseSession: Codable, Equatable {
    let localId: String
    var idToken: String
    var refreshToken: String
    let email: String
    var expiresAt: Date
}

struct UserProfile: Codable, Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    var email: String
    var displayName: String
    var nickname: String
    var avatarUrl: String?
    var friends: [String]
    var joinedChannels: [String]
}

struct NMessage: Identifiable, Hashable {
    let id: String
    let senderId: String
    let receiverId: String
    let text: String
    let date: Date
}

struct NChannel: Identifiable, Hashable {
    let id: String
    var name: String
    var username: String
    var description: String
    var ownerId: String
    var members: [String]
    var subscriberCount: Int
    var avatarUrl: String?

    var isSubscribed: Bool { false }
}

struct ChannelMessage: Identifiable, Hashable {
    let id: String
    let channelId: String
    let senderId: String
    let text: String
    let date: Date
}

struct FriendRequest: Identifiable, Hashable {
    let id: String
    let senderId: String
    let receiverId: String
    var status: String
    let date: Date
    var senderNickname: String = ""
}
