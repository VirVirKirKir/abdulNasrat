import Foundation

/// Читает публичную веб-версию Telegram-канала (t.me/s/<channel>).
/// API-ключи не нужны. Канал задаётся в настройках приложения.
enum TelegramSource {

    struct Message: Sendable {
        let id: String
        let date: Date?
        let text: String
    }

    static func fetch(channel: String, requireRegion: Bool) async -> SourceResult {
        var clean = channel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "t.me/", with: "")
            .replacingOccurrences(of: "@", with: "")
        if clean.hasPrefix("s/") {
            clean.removeFirst(2)
        }
        clean = clean.split(separator: "/").first.map(String.init) ?? ""

        guard !clean.isEmpty, let url = URL(string: "https://t.me/s/\(clean)") else {
            return SourceResult(events: [], report: SourceReport(
                name: "Telegram",
                urlString: channel,
                httpStatus: nil,
                messageCount: 0,
                eventCount: 0,
                error: "Некорректное имя канала"
            ))
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let html = String(decoding: data, as: UTF8.self)
            let messages = parseMessages(html)

            var events: [AlertEvent] = []
            for message in messages {
                guard !message.text.isEmpty else { continue }
                if requireRegion && !message.text.lowercased().contains("оренбург") { continue }
                guard let kind = AlertClassifier.classify(message.text) else { continue }
                events.append(AlertEvent(
                    id: "tg:\(clean):\(message.id)",
                    kind: kind,
                    date: message.date ?? Date(),
                    source: "@\(clean)",
                    rawText: message.text,
                    isTest: false
                ))
            }

            return SourceResult(events: events, report: SourceReport(
                name: "Telegram @\(clean)",
                urlString: url.absoluteString,
                httpStatus: status,
                messageCount: messages.count,
                eventCount: events.count,
                error: status == 200 ? nil : "HTTP \(status ?? 0)"
            ))
        } catch {
            return SourceResult(events: [], report: SourceReport(
                name: "Telegram @\(clean)",
                urlString: url.absoluteString,
                httpStatus: nil,
                messageCount: 0,
                eventCount: 0,
                error: error.localizedDescription
            ))
        }
    }

    // MARK: - Парсинг HTML

    static func parseMessages(_ html: String) -> [Message] {
        var result: [Message] = []
        let blocks = html.components(separatedBy: "tgme_widget_message_wrap")

        for block in blocks.dropFirst() {
            guard let idRange = block.range(of: "data-post=\"") else { continue }
            let afterID = block[idRange.upperBound...]
            guard let quote = afterID.firstIndex(of: "\"") else { continue }
            let post = String(afterID[..<quote])
            let messageID = post.split(separator: "/").last.map(String.init) ?? post

            var date: Date?
            if let dateRange = block.range(of: "datetime=\"") {
                let afterDate = block[dateRange.upperBound...]
                if let end = afterDate.firstIndex(of: "\"") {
                    let raw = String(afterDate[..<end])
                    date = ISO8601DateFormatter().date(from: raw)
                }
            }

            result.append(Message(id: messageID, date: date, text: extractText(block)))
        }

        return result
    }

    private static func extractText(_ block: String) -> String {
        guard let marker = block.range(of: "tgme_widget_message_text") else { return "" }
        guard let openTag = block.range(of: ">", range: marker.upperBound..<block.endIndex) else { return "" }
        let body = block[openTag.upperBound...]
        if let end = body.range(of: "</div>") {
            return stripHTML(String(body[..<end.lowerBound]))
        }
        return stripHTML(String(body.prefix(3000)))
    }

    static func stripHTML(_ source: String) -> String {
        var text = source
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")

        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&#x27;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&mdash;": "—",
            "&ndash;": "–",
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Определяет тип события по тексту сообщения.
enum AlertClassifier {

    static func classify(_ raw: String) -> AlertKind? {
        let text = raw
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        let isAllClear = text.contains("отбой")
        let mentionsUAV = contains(text, ["бпла", "беспилот", "дрон", "бпла"])
        let mentionsMissile = text.contains("ракетн")
        let mentionsSiren = text.contains("сирен")
        let mentionsAirRaid = contains(text, ["воздушн", "тревог"])

        if isAllClear {
            if mentionsMissile { return .missileAllClear }
            if mentionsUAV { return .uavAllClear }
            if mentionsSiren { return .sirensOff }
            if mentionsAirRaid { return .sirensOff }
            return nil
        }

        if mentionsSiren { return .sirensOn }

        if mentionsMissile && contains(text, ["опасн", "угроз", "летит", "пуск"]) {
            return .missileThreat
        }

        if mentionsUAV && contains(text, ["опасн", "угроз", "летят", "курс", "приближ", "атака"]) {
            return .uavThreat
        }

        return nil
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
