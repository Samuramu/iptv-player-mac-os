import Foundation

struct XtreamService {
    let baseURL: String
    let username: String
    let password: String

    struct AuthResponse: Decodable {
        let userInfo: UserInfo?
        let serverInfo: ServerInfo?

        enum CodingKeys: String, CodingKey {
            case userInfo = "user_info"
            case serverInfo = "server_info"
        }
    }

    struct UserInfo: Decodable {
        let username: String?
        let status: String?
        let expDate: String?
        let activeCons: String?
        let maxConnections: String?

        enum CodingKeys: String, CodingKey {
            case username
            case status
            case expDate = "exp_date"
            case activeCons = "active_cons"
            case maxConnections = "max_connections"
        }
    }

    struct ServerInfo: Decodable {
        let url: String?
        let port: String?
        let httpsPort: String?
        let serverProtocol: String?

        enum CodingKeys: String, CodingKey {
            case url
            case port
            case httpsPort = "https_port"
            case serverProtocol = "server_protocol"
        }
    }

    struct XtreamCategory: Decodable {
        let categoryId: String?
        let categoryName: String?
        let parentId: Int?

        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
            case categoryName = "category_name"
            case parentId = "parent_id"
        }
    }

    struct XtreamStream: Decodable {
        let num: Int?
        let name: String?
        let streamId: Int?
        let streamIcon: String?
        let epgChannelId: String?
        let categoryId: String?

        enum CodingKeys: String, CodingKey {
            case num
            case name
            case streamId = "stream_id"
            case streamIcon = "stream_icon"
            case epgChannelId = "epg_channel_id"
            case categoryId = "category_id"
        }
    }

    private func apiURL(action: String, extra: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: baseURL)
        if components?.path.isEmpty == true || components?.path == "/" {
            components?.path = "/player_api.php"
        } else if components?.path.hasSuffix("/") == true {
            components?.path += "player_api.php"
        }
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action),
        ]
        for (key, value) in extra {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    func authenticate() async throws -> AuthResponse {
        guard let url = apiURL(action: "") else {
            throw XtreamError.invalidURL
        }
        // For auth, we don't need action parameter
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.filter { $0.name != "action" }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func getLiveCategories() async throws -> [XtreamCategory] {
        guard let url = apiURL(action: "get_live_categories") else {
            throw XtreamError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([XtreamCategory].self, from: data)
    }

    func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamStream] {
        var extra: [String: String] = [:]
        if let categoryId { extra["category_id"] = categoryId }
        guard let url = apiURL(action: "get_live_streams", extra: extra) else {
            throw XtreamError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([XtreamStream].self, from: data)
    }

    func streamURL(for streamId: Int, extension ext: String = "m3u8") -> String {
        "\(baseURL)/live/\(username)/\(password)/\(streamId).\(ext)"
    }
}

enum XtreamError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Xtream Codes URL"
        case .authenticationFailed: return "Authentication failed"
        case .decodingFailed: return "Failed to decode response"
        }
    }
}
