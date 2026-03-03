import AppKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSString, NSImage>()
    private var activeTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func image(for urlString: String) async -> NSImage? {
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }

        if let task = activeTasks[urlString] {
            return await task.value
        }

        let task = Task<NSImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else { return nil }
                cache.setObject(image, forKey: urlString as NSString,
                              cost: data.count)
                return image
            } catch {
                return nil
            }
        }

        activeTasks[urlString] = task
        let result = await task.value
        activeTasks.removeValue(forKey: urlString)
        return result
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}

struct CachedAsyncImage: View {
    let urlString: String
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            guard !urlString.isEmpty else {
                isLoading = false
                return
            }
            image = await ImageCache.shared.image(for: urlString)
            isLoading = false
        }
    }
}
