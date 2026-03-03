import Foundation

struct M3UParser {
    struct ParsedChannel {
        let name: String
        let streamURL: String
        let logoURL: String
        let groupTitle: String
        let tvgId: String
        let tvgName: String
    }

    static func parse(content: String) -> [ParsedChannel] {
        var channels: [ParsedChannel] = []
        let lines = content.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#EXTINF:") {
                let name = extractDisplayName(from: line)
                let logoURL = extractAttribute(named: "tvg-logo", from: line)
                let groupTitle = extractAttribute(named: "group-title", from: line)
                let tvgId = extractAttribute(named: "tvg-id", from: line)
                let tvgName = extractAttribute(named: "tvg-name", from: line)

                i += 1
                while i < lines.count {
                    let urlLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if !urlLine.isEmpty && !urlLine.hasPrefix("#") {
                        let channel = ParsedChannel(
                            name: name,
                            streamURL: urlLine,
                            logoURL: logoURL,
                            groupTitle: groupTitle.isEmpty ? "Uncategorized" : groupTitle,
                            tvgId: tvgId,
                            tvgName: tvgName
                        )
                        channels.append(channel)
                        break
                    }
                    i += 1
                }
            }
            i += 1
        }

        return channels
    }

    static func parse(url: URL) async throws -> [ParsedChannel] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3UParserError.invalidEncoding
        }
        return parse(content: content)
    }

    private static func extractAttribute(named name: String, from line: String) -> String {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return ""
        }
        return String(line[range])
    }

    private static func extractDisplayName(from line: String) -> String {
        guard let commaIndex = line.lastIndex(of: ",") else {
            return "Unknown Channel"
        }
        let name = String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unknown Channel" : name
    }
}

enum M3UParserError: LocalizedError {
    case invalidEncoding
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Could not decode M3U file content"
        case .invalidURL: return "Invalid M3U URL"
        }
    }
}
