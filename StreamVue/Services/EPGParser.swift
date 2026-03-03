import Foundation

struct EPGParser {
    struct ParsedProgram {
        let channelId: String
        let title: String
        let description: String
        let startTime: Date
        let stopTime: Date
    }

    static func parse(data: Data) -> [ParsedProgram] {
        let parser = XMLTVParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.programs
    }

    static func parse(url: URL) async throws -> [ParsedProgram] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return parse(data: data)
    }
}

private class XMLTVParserDelegate: NSObject, XMLParserDelegate {
    var programs: [EPGParser.ParsedProgram] = []

    private var currentElement = ""
    private var currentChannelId = ""
    private var currentTitle = ""
    private var currentDesc = ""
    private var currentStart: Date?
    private var currentStop: Date?
    private var isInProgramme = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateFormatterAlt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "programme" {
            isInProgramme = true
            currentChannelId = attributeDict["channel"] ?? ""
            currentTitle = ""
            currentDesc = ""

            if let startStr = attributeDict["start"] {
                currentStart = Self.dateFormatter.date(from: startStr)
                    ?? Self.dateFormatterAlt.date(from: startStr)
            }
            if let stopStr = attributeDict["stop"] {
                currentStop = Self.dateFormatter.date(from: stopStr)
                    ?? Self.dateFormatterAlt.date(from: stopStr)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInProgramme else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "desc":
            currentDesc += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "programme", let start = currentStart, let stop = currentStop {
            let program = EPGParser.ParsedProgram(
                channelId: currentChannelId,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: start,
                stopTime: stop
            )
            programs.append(program)
            isInProgramme = false
        }
        if elementName == "title" || elementName == "desc" {
            currentElement = ""
        }
    }
}
