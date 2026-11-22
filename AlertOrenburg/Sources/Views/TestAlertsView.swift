import SwiftUI

struct TestAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var center = AlertCenter.shared
    @ObservedObject private var settings = AlertCenter.shared.settings

    @State private var sending: AlertKind?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AlertKind.allCases) { kind in
                        Button {
                            send(kind)
                        } label: {
                            row(kind)
                        }
                        .disabled(sending != nil)
                    }
                } footer: {
                    Text("Уведомление приходит сразу, даже если приложение открыто. Для сирен используется твой звук (sirens.caf), для остальных — системный.")
                }

                Section {
                    Button {
                        sendAll()
                    } label: {
                        Label("Отправить все 6 подряд", systemImage: "play.circle.fill")
                    }
                    .disabled(sending != nil)

                    Toggle("Звук уведомлений", isOn: $settings.soundEnabled)
                }
            }
            .navigationTitle("Тест уведомлений")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func row(_ kind: AlertKind) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AlertGlyph(kind: kind, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(kind.notificationBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            if sending == kind {
                ProgressView().controlSize(.small)
            }
        }
        .contentShape(Rectangle())
    }

    private func send(_ kind: AlertKind) {
        sending = kind
        Task {
            await center.sendTest(kind)
            try? await Task.sleep(for: .seconds(1))
            sending = nil
        }
    }

    private func sendAll() {
        Task {
            for kind in AlertKind.allCases {
                sending = kind
                await center.sendTest(kind)
                try? await Task.sleep(for: .seconds(2))
            }
            sending = nil
        }
    }
}
