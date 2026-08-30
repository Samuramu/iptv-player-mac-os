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
                Button("Play/Pause") { PlaybackCommands.post(.playPause) }
                Button("Next Channel") { PlaybackCommands.post(.nextChannel) }
                Button("Previous Channel") { PlaybackCommands.post(.previousChannel) }
                Divider()
                Button("Toggle Fullscreen") { PlaybackCommands.post(.toggleFullscreen) }
                Text("Shortcuts: Space, ↑/↓, ←/→ volume, F fullscreen, Esc exit")
            }
        }
    }
}
