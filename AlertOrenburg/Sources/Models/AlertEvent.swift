import Foundation

/// Одно событие: угроза, отбой или сирены.
struct AlertEvent: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: AlertKind
    var date: Date
    var source: String
    var rawText: String?
    var isTest: Bool = false

    var kindID: String { kind.rawValue }
}
