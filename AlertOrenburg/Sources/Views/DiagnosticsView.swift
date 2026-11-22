import SwiftUI
import UserNotifications

struct DiagnosticsView: View {
    @ObservedObject private var center = AlertCenter.shared
    @ObservedObject private var settings = AlertCenter.shared.settings

    var body: some View {
        List {
            Section("Состояние") {
                LabeledContent("Уведомления", value: permissionText)
                LabeledContent(
                    "Звук сирены",
                    value: center.soundFileAvailable() ? "sirens.caf найден" : "не найден"
                )
                LabeledContent("Последняя проверка", value: lastCheckedText)
                LabeledContent(
                    "Фоновое обновление",
                    value: settings.backgroundRefresh ? "включено" : "выключено"
                )

                if let error = center.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if center.reports.isEmpty {
                    Text("Проверок ещё не было. Нажми «Проверить сейчас».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(center.reports) { report in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(report.name)
                                .font(.subheadline.weight(.semibold))

                            Text(report.urlString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 10) {
                                if let status = report.httpStatus {
                                    Text("HTTP \(status)")
                                }
                                Text("сообщений: \(report.messageCount)")
                                Text("событий: \(report.eventCount)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if let error = report.error {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Источники")
            } footer: {
                Text("Если «сообщений: 0», канал, скорее всего, не существует или закрыт. Проверь имя канала в настройках.")
            }

            Section {
                Button {
                    Task { await center.refresh() }
                } label: {
                    if center.isRefreshing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Проверяю…")
                        }
                    } else {
                        Text("Проверить сейчас")
                    }
                }
                .disabled(center.isRefreshing)
            }
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var permissionText: String {
        switch center.permission {
        case .authorized: return "разрешены"
        case .provisional: return "тихие"
        case .denied: return "запрещены"
        case .ephemeral: return "временно"
        case .notDetermined: return "не запрошены"
        @unknown default: return "неизвестно"
        }
    }

    private var lastCheckedText: String {
        guard let last = center.lastChecked else { return "—" }
        return last.formatted(date: .abbreviated, time: .standard)
    }
}
