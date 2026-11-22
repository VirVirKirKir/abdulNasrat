import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = AlertCenter.shared
    @ObservedObject private var settings = AlertCenter.shared.settings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Звук уведомлений", isOn: $settings.soundEnabled)
                    Toggle("Time Sensitive (пробивать фокус)", isOn: $settings.timeSensitive)
                    Button("Настройки уведомлений iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Уведомления")
                } footer: {
                    Text("Time Sensitive требует entitlement и платный аккаунт разработчика. Без него iOS доставит уведомление как обычное.")
                }

                Section {
                    Toggle("Telegram-каналы", isOn: $settings.useTelegram)

                    if settings.useTelegram {
                        TextField("mchs_orenburg, orenburg_official", text: $settings.channels)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Toggle("Только сообщения про Оренбург", isOn: $settings.regionFilter)
                    }
                } header: {
                    Text("Источник: Telegram")
                } footer: {
                    Text("Читается публичная веб-версия канала (t.me/s/…). Укажи каналы, которые реально публикуют оповещения по области, и проверь их в «Диагностике».")
                }

                Section {
                    Toggle("JSON-лента", isOn: $settings.useJSONFeed)

                    if settings.useJSONFeed {
                        TextField("https://example.com/alerts.json", text: $settings.jsonFeedURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Источник: JSON")
                } footer: {
                    Text("Подходит свой сервер, n8n или Cloudflare Worker. Формат описан в README (docs/API.md).")
                }

                Section {
                    Toggle("Фоновое обновление", isOn: $settings.backgroundRefresh)
                    Button("Проверить сейчас") {
                        Task { await center.refresh() }
                    }
                } header: {
                    Text("Обновление")
                } footer: {
                    Text("В фоне iOS даёт приложению время не чаще, чем раз в 15–60 минут, и только если приложением пользуются. Мгновенные push требуют сервер и платный аккаунт разработчика.")
                }

                Section("Дополнительно") {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Диагностика источников", systemImage: "stethoscope")
                    }
                }

                Section {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Регион", value: "Оренбургская область")
                    LabeledContent("Экстренный номер", value: "112")
                } header: {
                    Text("О приложении")
                } footer: {
                    Text("Неофициальное приложение. Не заменяет оповещения МЧС и РСЧС. При угрозе звони 112 и следуй указаниям властей.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
