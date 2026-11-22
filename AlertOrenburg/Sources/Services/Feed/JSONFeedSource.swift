import Foundation

/// Универсальная JSON-лента (свой сервер, n8n, Cloudflare Worker и т.п.).
///
/// Формат:
/// {
///   "alerts": [
///     { "id": "123", "kind": "uav_threat", "issuedAt": "2026-11-22T18:40:00Z",
///       "text": "необязательный исходный текст", "source": "МЧС" }
///   ]
/// }
enum JSONFeedSource {

    private struct Payload: Decodable {
        var alerts: [Item]?
        var events: [Item]?
        var items: [Item]?
    }

    private struct Item: Decodable {
        var id: String?
        var kind: String?
        var type: String?
        var issuedAt: String?
        var date: String?
        var timestamp: Double?
        var text: String?
        var message: String?
        var source: String?
    }

    static func fetch(url: URL) async -> SourceResult {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode

            guard status == 200 else {
                return SourceResult(events: [], report: SourceReport(
                    name: "JSON-лента",
                    urlString: url.absoluteString,
                    httpStatus: status,
                    messageCount: 0,
                    eventCount: 0,
                    error: "HTTP \(status ?? 0)"
                ))
            }

            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let items = payload.alerts ?? payload.events ?? payload.items ?? []
            var events: [AlertEvent] = []

            for item in items {
                guard
                    let rawKind = item.kind ?? item.type,
                    let kind = AlertKind.from(rawKind)
                else { continue }

                let date = parseDate(item.issuedAt ?? item.date)
                    ?? item.timestamp.map { Date(timeIntervalSince1970: $0 > 2_000_000_000 ? $0 / 1000 : $0) }
                    ?? Date()

                let id = item.id ?? "json:\(kind.rawValue):\(Int(date.timeIntervalSince1970))"

                events.append(AlertEvent(
                    id: "json:\(id)",
                    kind: kind,
                    date: date,
                    source: item.source ?? url.host ?? "JSON",
                    rawText: item.text ?? item.message,
                    isTest: false
                ))
            }

            return SourceResult(events: events, report: SourceReport(
                name: "JSON-лента",
                urlString: url.absoluteString,
                httpStatus: status,
                messageCount: items.count,
                eventCount: events.count,
                error: nil
            ))
        } catch {
            return SourceResult(events: [], report: SourceReport(
                name: "JSON-лента",
                urlString: url.absoluteString,
                httpStatus: nil,
                messageCount: 0,
                eventCount: 0,
                error: error.localizedDescription
            ))
        }
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fallback.date(from: raw)
    }
}
