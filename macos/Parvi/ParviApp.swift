import SwiftUI
import ParviKit

@main
struct ParviApp: App {
    @StateObject private var model = ChatModel(runtime: MacErlangRuntime())
    var body: some Scene {
        WindowGroup("Parvi") {
            ParviChatView(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
        .defaultSize(width: 960, height: 680)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
