import SwiftUI
import ParviKit

@main
struct ParviApp: App {
    @StateObject private var model = ChatModel(runtime: IOSErlangRuntime())

    var body: some Scene {
        WindowGroup {
            ParviChatView(model: model)
        }
    }
}
