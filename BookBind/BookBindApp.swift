import SwiftUI

@main
struct BookBindApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Masterwork…") {
                    NotificationCenter.default.post(name: .bookBindNewMasterwork, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let bookBindNewMasterwork = Notification.Name("bookBindNewMasterwork")
}
