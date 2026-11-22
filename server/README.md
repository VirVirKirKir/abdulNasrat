# Сервер (черновик)

Нужен только для того, чтобы оповещения приходили **при закрытом приложении**. Без него приложение работает на локальных уведомлениях и фоновом обновлении.

## Запуск

```bash
cd server
TELEGRAM_CHANNELS=mchs_orenburg,orenburg_official PORT=8080 node server.mjs
```

Проверка:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/alerts
```

В приложении: **Настройки → JSON-лента** → `http://<адрес>:8080/alerts`.

## Push через APNs

1. Нужен платный Apple Developer Program.
2. Создай APNs-ключ (Keys → + → Apple Push Notifications service) и скачай `.p8` (один раз).
3. Запусти:

```bash
APNS_KEY_FILE=./AuthKey_ABC123.p8 \
APNS_KEY_ID=ABC123DEFG \
APNS_TEAM_ID=TEAM123456 \
APNS_TOPIC=ru.alert.orenburg \
TELEGRAM_CHANNELS=mchs_orenburg \
node server.mjs
```

4. В приложении нужно добавить регистрацию на push (`registerForRemoteNotifications`) и отправку токена на `POST /devices`. В текущей сборке этого нет — это следующий шаг.

## Тест

```bash
curl -X POST "http://localhost:8080/test?kind=sirens_on&token=СЕКРЕТ"
```

## Ограничения

- Один инстанс, состояние в JSON-файле, без ретраев и очередей.
- Telegram-парсер зависит от разметки `t.me/s/...` — она может измениться.
- Не является официальным источником оповещений.
