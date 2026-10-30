import SwiftUI
import ParviKit

@main
struct ParviApp: App {
    @StateObject private var model = ChatModel(runtime: MacErlangRuntime())
    var body: some Scene {
        WindowGroup("Parvi") {
            ParviChatView(model: model)
                .frame(minWidth: 420, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
        .defaultSize(width: 1080, height: 780)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
