// Черновик сервера для «Тревога · Оренбург».
// Node.js 20+, без внешних зависимостей.
//
// Умеет:
//   GET  /health              — статус
//   GET  /alerts              — JSON-лента для приложения (см. docs/API.md)
//   POST /devices  {token}    — регистрация APNs-токена
//   POST /test?kind=uav_threat&token=... — тестовое событие (+ push, если настроен APNs)
//
// Переменные окружения:
//   PORT=8080
//   TELEGRAM_CHANNELS=mchs_orenburg,orenburg_official
//   POLL_SECONDS=60
//   ADMIN_TOKEN=секрет
//   DATA_FILE=./data.json
//   APNS_KEY_FILE=./AuthKey_XXX.p8
//   APNS_KEY_ID=XXXXXXXXXX
//   APNS_TEAM_ID=XXXXXXXXXX
//   APNS_TOPIC=ru.alert.orenburg
//
// ВАЖНО: это заготовка. Она не проверена в бою и не является официальным источником.

import http from "node:http";
import http2 from "node:http2";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const PORT = Number(process.env.PORT || 8080);
const CHANNELS = (process.env.TELEGRAM_CHANNELS || "")
  .split(",")
  .map((s) => s.trim().replace(/^@/, ""))
  .filter(Boolean);
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 60);
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "";
const DATA_FILE = process.env.DATA_FILE || path.join(process.cwd(), "data.json");

const APNS = {
  keyFile: process.env.APNS_KEY_FILE || "",
  keyId: process.env.APNS_KEY_ID || "",
  teamId: process.env.APNS_TEAM_ID || "",
  topic: process.env.APNS_TOPIC || "ru.alert.orenburg",
};

const state = {
  alerts: [],
  devices: new Set(),
  seen: new Set(),
};

// ---------- persistence ----------

function load() {
  try {
    const raw = JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
    state.alerts = Array.isArray(raw.alerts) ? raw.alerts : [];
    state.devices = new Set(Array.isArray(raw.devices) ? raw.devices : []);
    state.seen = new Set(state.alerts.map((a) => a.id));
  } catch {
    /* первый запуск */
  }
}

function save() {
  try {
    fs.writeFileSync(
      DATA_FILE,
      JSON.stringify({ alerts: state.alerts.slice(0, 300), devices: [...state.devices] }, null, 2)
    );
  } catch (error) {
    console.error("save failed:", error.message);
  }
}

// ---------- тексты ----------

const KINDS = {
  uav_threat: {
    title: "⚠️ Угроза БПЛА",
    body: "Внимание! На территории Оренбургской области действует угроза БПЛА, будьте бдительны! Телефон спасения: 112",
  },
  missile_threat: {
    title: "🚀 Ракетная опасность",
    body: "Внимание! На территории Оренбургской области действует РАКЕТНАЯ ОПАСНОСТЬ! Будьте бдительны! Телефон спасения: 112",
  },
  uav_all_clear: {
    title: "✅ Отбой угрозы БПЛА",
    body: "Внимание! Внимание! Отбой угрозы БПЛА!",
  },
  missile_all_clear: {
    title: "✅ Отбой ракетной опасности",
    body: "Внимание! Внимание! Отбой РАКЕТНОЙ ОПАСНОСТИ!",
  },
  sirens_on: {
    title: "🚨 ЗВУЧАТ СИРЕНЫ",
    body: "ВНИМАНИЕ! ВНИМАНИЕ! НА ТЕРРИТОРИИ ОРЕНБУРГСКОЙ ОБЛАСТИ ЗВУЧАТ СИРЕНЫ! ТЕЛЕФОН СПАСЕНИЯ: 112!!! БУДЬТЕ БДИТЕЛЬНЫ!",
  },
  sirens_off: {
    title: "✅ Отбой воздушной тревоги",
    body: "Внимание! Внимание! Отбой воздушной тревоги! Отбой воздушной тревоги!",
  },
};

function classify(raw) {
  const text = String(raw || "").toLowerCase().replace(/ё/g, "е");
  const has = (...words) => words.some((w) => text.includes(w));
  const allClear = text.includes("отбой");
  const uav = has("бпла", "беспилот", "дрон");
  const missile = text.includes("ракетн");
  const siren = text.includes("сирен");

  if (allClear) {
    if (missile) return "missile_all_clear";
    if (uav) return "uav_all_clear";
    if (siren || has("воздушн", "тревог")) return "sirens_off";
    return null;
  }
  if (siren) return "sirens_on";
  if (missile && has("опасн", "угроз", "летит", "пуск")) return "missile_threat";
  if (uav && has("опасн", "угроз", "летят", "курс", "приближ", "атака")) return "uav_threat";
  return null;
}

// ---------- telegram ----------

function stripHTML(html) {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .trim();
}

function parseTelegram(html) {
  const messages = [];
  const blocks = html.split("tgme_widget_message_wrap").slice(1);
  for (const block of blocks) {
    const postMatch = block.match(/data-post="([^"]+)"/);
    if (!postMatch) continue;
    const id = postMatch[1].split("/").pop();
    const dateMatch = block.match(/datetime="([^"]+)"/);
    const marker = block.indexOf("tgme_widget_message_text");
    let text = "";
    if (marker !== -1) {
      const start = block.indexOf(">", marker);
      const end = block.indexOf("</div>", start);
      text = stripHTML(block.slice(start + 1, end === -1 ? start + 3000 : end));
    }
    messages.push({
      id,
      date: dateMatch ? new Date(dateMatch[1]) : new Date(),
      text,
    });
  }
  return messages;
}

async function pollChannel(channel) {
  const url = `https://t.me/s/${encodeURIComponent(channel)}`;
  const response = await fetch(url, {
    headers: {
      "user-agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36",
      "accept-language": "ru-RU,ru;q=0.9",
    },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const html = await response.text();
  return parseTelegram(html);
}

async function pollAll() {
  for (const channel of CHANNELS) {
    try {
      const messages = await pollChannel(channel);
      for (const message of messages) {
        const kind = classify(message.text);
        if (!kind) continue;
        const id = `tg:${channel}:${message.id}`;
        if (state.seen.has(id)) continue;
        state.seen.add(id);
        addAlert({ id, kind, issuedAt: message.date.toISOString(), source: `@${channel}`, text: message.text });
      }
      console.log(`[poll] @${channel}: ${messages.length} messages`);
    } catch (error) {
      console.error(`[poll] @${channel}: ${error.message}`);
    }
  }
}

// ---------- alerts ----------

async function addAlert({ id, kind, issuedAt, source, text }) {
  const alert = { id, kind, issuedAt, source, text };
  state.alerts.unshift(alert);
  state.alerts = state.alerts.slice(0, 300);
  save();
  console.log(`[alert] ${kind} (${id})`);
  await broadcast(alert);
  return alert;
}

// ---------- APNs ----------

let cachedJWT = { value: "", createdAt: 0 };

function apnsJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT.value && now - cachedJWT.createdAt < 3000) return cachedJWT.value;

  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: APNS.keyId })).toString("base64url");
  const claims = Buffer.from(JSON.stringify({ iss: APNS.teamId, iat: now })).toString("base64url");
  const signer = crypto.createSign("sha256");
  signer.update(`${header}.${claims}`);
  const signature = signer.sign({
    key: fs.readFileSync(APNS.keyFile, "utf8"),
    dsaEncoding: "ieee-p1363",
  });
  cachedJWT = { value: `${header}.${claims}.${signature.toString("base64url")}`, createdAt: now };
  return cachedJWT.value;
}

function apnsEnabled() {
  return Boolean(APNS.keyFile && APNS.keyId && APNS.teamId && fs.existsSync(APNS.keyFile));
}

function pushOne(deviceToken, alert) {
  const meta = KINDS[alert.kind] || KINDS.uav_threat;
  const payload = JSON.stringify({
    aps: {
      alert: { title: meta.title, body: meta.body },
      sound: alert.kind === "sirens_on" ? "sirens.caf" : "default",
      category: alert.kind,
      "thread-id": "orenburg-alerts",
      "interruption-level": "time-sensitive",
    },
    kind: alert.kind,
    eventID: alert.id,
  });

  return new Promise((resolve) => {
    const client = http2.connect("https://api.push.apple.com:443");
    client.on("error", (error) => resolve({ ok: false, status: 0, body: error.message }));

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      "apns-topic": APNS.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      authorization: `bearer ${apnsJWT()}`,
      "content-type": "application/json",
    });

    let status = 0;
    let body = "";
    request.on("response", (headers) => {
      status = headers[":status"] || 0;
    });
    request.setEncoding("utf8");
    request.on("data", (chunk) => (body += chunk));
    request.on("end", () => {
      client.close();
      resolve({ ok: status === 200, status, body });
    });
    request.end(payload);
  });
}

async function broadcast(alert) {
  if (!apnsEnabled() || state.devices.size === 0) return;
  for (const token of [...state.devices]) {
    const result = await pushOne(token, alert);
    if (!result.ok) {
      console.error(`[apns] ${token.slice(0, 8)}…: ${result.status} ${result.body}`);
      if (result.status === 410 || result.status === 400) {
        state.devices.delete(token);
        save();
      }
    }
  }
}

// ---------- HTTP ----------

function json(response, status, data) {
  const body = JSON.stringify(data);
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "access-control-allow-origin": "*",
  });
  response.end(body);
}

function readBody(request) {
  return new Promise((resolve) => {
    let body = "";
    request.on("data", (chunk) => (body += chunk));
    request.on("end", () => resolve(body));
  });
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://localhost:${PORT}`);

  if (request.method === "GET" && url.pathname === "/health") {
    return json(response, 200, {
      ok: true,
      alerts: state.alerts.length,
      devices: state.devices.size,
      channels: CHANNELS,
      apns: apnsEnabled(),
    });
  }

  if (request.method === "GET" && url.pathname === "/alerts") {
    return json(response, 200, { alerts: state.alerts.slice(0, 50) });
  }

  if (request.method === "POST" && url.pathname === "/devices") {
    try {
      const body = JSON.parse(await readBody(request) || "{}");
      const token = String(body.token || "").replace(/[^a-fA-F0-9]/g, "");
      if (token.length < 32) return json(response, 400, { error: "bad token" });
      state.devices.add(token);
      save();
      return json(response, 200, { ok: true, devices: state.devices.size });
    } catch {
      return json(response, 400, { error: "bad json" });
    }
  }

  if (request.method === "POST" && url.pathname === "/test") {
    if (ADMIN_TOKEN && url.searchParams.get("token") !== ADMIN_TOKEN) {
      return json(response, 403, { error: "forbidden" });
    }
    const kind = url.searchParams.get("kind") || "uav_threat";
    if (!KINDS[kind]) return json(response, 400, { error: "unknown kind" });
    const alert = await addAlert({
      id: `test:${kind}:${Date.now()}`,
      kind,
      issuedAt: new Date().toISOString(),
      source: "test",
      text: "",
    });
    return json(response, 200, { ok: true, alert });
  }

  json(response, 404, { error: "not found" });
});

load();

server.listen(PORT, () => {
  console.log(`alert-orenburg server on :${PORT}`);
  console.log(`channels: ${CHANNELS.join(", ") || "(none)"}`);
  if (CHANNELS.length) {
    pollAll();
    setInterval(pollAll, Math.max(30, POLL_SECONDS) * 1000);
  }
});
