import SwiftUI

/// Типы событий, которые умеет показывать приложение.
enum AlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case uavThreat = "uav_threat"
    case missileThreat = "missile_threat"
    case uavAllClear = "uav_all_clear"
    case missileAllClear = "missile_all_clear"
    case sirensOn = "sirens_on"
    case sirensOff = "sirens_off"

    var id: String { rawValue }

    // MARK: - Заголовки

    var title: String {
        switch self {
        case .uavThreat: return "Угроза БПЛА"
        case .missileThreat: return "Ракетная опасность"
        case .uavAllClear: return "Отбой угрозы БПЛА"
        case .missileAllClear: return "Отбой ракетной опасности"
        case .sirensOn: return "Звучат сирены"
        case .sirensOff: return "Отбой воздушной тревоги"
        }
    }

    var isDanger: Bool {
        switch self {
        case .uavThreat, .missileThreat, .sirensOn: return true
        case .uavAllClear, .missileAllClear, .sirensOff: return false
        }
    }

    var accent: Color {
        switch self {
        case .uavThreat:
            return Color(red: 1.00, green: 0.58, blue: 0.10)
        case .missileThreat:
            return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .sirensOn:
            return Color(red: 1.00, green: 0.17, blue: 0.33)
        case .uavAllClear, .missileAllClear, .sirensOff:
            return Color(red: 0.22, green: 0.80, blue: 0.47)
        }
    }

    // MARK: - Текст уведомления

    var notificationTitle: String {
        switch self {
        case .uavThreat: return "⚠️ Угроза БПЛА"
        case .missileThreat: return "🚀 Ракетная опасность"
        case .uavAllClear: return "✅ Отбой угрозы БПЛА"
        case .missileAllClear: return "✅ Отбой ракетной опасности"
        case .sirensOn: return "🚨 ЗВУЧАТ СИРЕНЫ"
        case .sirensOff: return "✅ Отбой воздушной тревоги"
        }
    }

    var notificationBody: String {
        switch self {
        case .uavThreat:
            return "Внимание! На территории Оренбургской области действует угроза БПЛА, будьте бдительны! Телефон спасения: 112"
        case .missileThreat:
            return "Внимание! На территории Оренбургской области действует РАКЕТНАЯ ОПАСНОСТЬ! Будьте бдительны! Телефон спасения: 112"
        case .uavAllClear:
            return "Внимание! Внимание! Отбой угрозы БПЛА!"
        case .missileAllClear:
            return "Внимание! Внимание! Отбой РАКЕТНОЙ ОПАСНОСТИ!"
        case .sirensOn:
            return "ВНИМАНИЕ! ВНИМАНИЕ! НА ТЕРРИТОРИИ ОРЕНБУРГСКОЙ ОБЛАСТИ ЗВУЧАТ СИРЕНЫ! ТЕЛЕФОН СПАСЕНИЯ: 112!!! БУДЬТЕ БДИТЕЛЬНЫ!"
        case .sirensOff:
            return "Внимание! Внимание! Отбой воздушной тревоги! Отбой воздушной тревоги!"
        }
    }

    /// Имя файла звука в бандле. Конвертируется из sirens.mp3 при сборке.
    var soundFileName: String? {
        switch self {
        case .sirensOn: return "sirens.caf"
        default: return nil
        }
    }

    /// Приоритет для сортировки: чем больше, тем важнее.
    var priority: Int {
        switch self {
        case .sirensOn: return 60
        case .missileThreat: return 50
        case .uavThreat: return 40
        case .missileAllClear: return 20
        case .uavAllClear: return 10
        case .sirensOff: return 5
        }
    }

    // MARK: - Разбор строк из внешних источников

    static func from(_ raw: String) -> AlertKind? {
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if let kind = AlertKind(rawValue: normalized) { return kind }
        switch normalized {
        case "uav", "drone", "bpla", "бпла", "угроза_бпла", "uav_alert":
            return .uavThreat
        case "missile", "rocket", "ракета", "ракетная_опасность", "missile_alert":
            return .missileThreat
        case "uav_clear", "uav_allclear", "all_clear_uav", "отбой_бпла":
            return .uavAllClear
        case "missile_clear", "missile_allclear", "all_clear_missile", "отбой_ракеты":
            return .missileAllClear
        case "sirens", "siren", "сирены", "sirens_on":
            return .sirensOn
        case "sirens_off", "all_clear", "отбой_сирен":
            return .sirensOff
        default:
            return nil
        }
    }
}
