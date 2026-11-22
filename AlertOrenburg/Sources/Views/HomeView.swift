import SwiftUI
import UIKit
import UserNotifications

struct HomeView: View {
    @ObservedObject private var center = AlertCenter.shared

    @State private var showTests = false
    @State private var showSettings = false

    /// Угроза показывается только если последнее событие — опасность.
    /// После отбоя карточка снова зелёная.
    private var currentDanger: AlertEvent? {
        guard let latest = center.alerts.first, latest.kind.isDanger else { return nil }
        return latest
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard

                if center.permission != .authorized && center.permission != .provisional {
                    permissionCard
                }

                quickActions

                if !center.alerts.isEmpty {
                    historySection
                } else {
                    emptyHistory
                }

                disclaimer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(background)
        .refreshable {
            await center.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Настройки")
            }
        }
        .sheet(isPresented: $showTests) {
            TestAlertsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await center.bootstrap()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(90))
                if Task.isCancelled { break }
                await center.refresh()
            }
        }
    }

    // MARK: - Карточка статуса

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                statusIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentDanger?.kind.title ?? "Угроз не зафиксировано")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(currentDanger?.kind.notificationBody ?? "Оренбургская область · мониторинг включён")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text(checkText)
                Spacer()
                if center.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke((currentDanger?.kind.accent ?? Color.green).opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let danger = currentDanger {
            AlertGlyph(kind: danger.kind, size: 64)
        } else {
            ZStack {
                Circle().fill(Color.green.opacity(0.16))
                Circle().stroke(Color.green.opacity(0.45), lineWidth: 1)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            .frame(width: 64, height: 64)
        }
    }

    private var checkText: String {
        if let last = center.lastChecked {
            return "Проверено: \(last.formatted(date: .omitted, time: .shortened))"
        }
        return "Проверок ещё не было"
    }

    // MARK: - Разрешение на уведомления

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Уведомления выключены", systemImage: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(center.permission == .denied
                 ? "Разреши уведомления в настройках iOS — иначе оповещения не покажутся."
                 : "Разреши уведомления, чтобы получать оповещения об угрозах и сиренах.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                if center.permission == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    Task { await center.requestPermission() }
                }
            } label: {
                Text(center.permission == .denied ? "Открыть настройки iOS" : "Разрешить уведомления")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    // MARK: - Действия

    private var quickActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await center.refresh() }
            } label: {
                Label("Проверить сейчас", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                showTests = true
            } label: {
                Label("Тест уведомлений", systemImage: "bell.badge.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - История

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("История")
                    .font(.headline)
                Spacer()
                Button("Очистить") {
                    center.clearHistory()
                }
                .font(.caption)
            }

            ForEach(center.alerts.prefix(40)) { event in
                AlertRow(event: event)
            }
        }
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("История пуста")
                .font(.headline)
            Text("Нажми «Тест уведомлений», чтобы проверить все 6 типов: угроза БПЛА, ракетная опасность, отбои и сирены.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Дисклеймер

    private var disclaimer: some View {
        Text("Приложение не является официальным сервисом МЧС. В экстренной ситуации звони 112 и следуй указаниям властей.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .padding(.bottom, 24)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.08, blue: 0.13),
                Color(red: 0.02, green: 0.03, blue: 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
