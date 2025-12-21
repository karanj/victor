import SwiftUI

@main
struct VictorApp: App {
    @State private var siteViewModel = SiteViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(siteViewModel: siteViewModel)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Hugo Site...") {
                    Task {
                        await siteViewModel.openSiteFolder()
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
