import SwiftUI

@main
struct MacFindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MacFind") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
