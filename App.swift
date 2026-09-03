import SwiftUI

@main
struct BreatheApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 460, minHeight: 640)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 760)
    }
}
