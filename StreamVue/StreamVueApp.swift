import SwiftUI
import SwiftData

@main
struct StreamVueApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Provider.self,
            Channel.self,
            ChannelCategory.self,
            EPGProgram.self,
            Favorite.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Playback") {
                Button("Play/Pause") {}
                    .keyboardShortcut(" ", modifiers: [])
                Button("Next Channel") {}
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("Previous Channel") {}
                    .keyboardShortcut(.upArrow, modifiers: [])
                Divider()
                Button("Toggle Fullscreen") {}
                    .keyboardShortcut("f", modifiers: [])
            }
        }
    }
}
