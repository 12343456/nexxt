# NEXXT — native iPad SwiftUI build

This build is synchronized with the NEXXT website's Firestore data model.

## Friends
- The canonical friend list is `users/{uid}.friends`, exactly as on the NEXXT website.
- Chats show only those friends.
- Friend requests use the website's `friendRequests` collection and `fromUid` / `toUid` / `status` fields.
- Accepting a request writes both UIDs into both users' `friends` arrays and removes the request, matching the website behavior.

## Channels
- The Channels screen shows only channels where the current user is a member or owner.
- The native app queries only matching channels instead of downloading the complete `channels` collection.

## Keyboard
All editable inputs use UIKit-backed `UITextField` / `UITextView` through `UIViewRepresentable`.
This intentionally avoids pure SwiftUI `TextField` / `TextEditor`, which were the unreliable part on iPad Swift Playgrounds.

The wrapper updates its coordinator on every SwiftUI update, uses the normal UIKit first-responder system, and provides a keyboard-toolbar "Готово" button in the main input screens.

## IMPORTANT — Swift Playgrounds
Delete/replace older duplicate Swift files. The project should contain one copy of each source file and exactly one `@main` declaration (`NEXXTApp.swift`).

Do not keep an older `NEXXTTextInput.swift`, `FirebaseREST.swift`, `ChatView.swift`, `FriendsView.swift`, `MainView.swift`, `ChannelsView.swift`, or `AuthView.swift` alongside these files.

`FIRESTORE_RULES.txt` contains the test rules used by the project.
