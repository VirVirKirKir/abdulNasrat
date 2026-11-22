// Generates a 1024x1024 app icon PNG without external dependencies.
// Usage: node tools/make-icon.js
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const S = 1024;
const SS = 2; // supersampling factor
const W = S * SS;

const buf = new Float64Array(W * W * 3);

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
function mix(a, b, t) { return a + (b - a) * t; }
function hex(h) {
  return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
}
const BG_TOP = hex("#12233F");
const BG_BOT = hex("#050C18");
const GLOW = hex("#1E4B85");
const TRI_FILL = hex("#0D1E33");
const ORANGE = hex("#FFB020");
const WHITE = [255, 255, 255];
const FLAME = hex("#FF6A00");

function px(x, y, c, a) {
  if (x < 0 || y < 0 || x >= W || y >= W) return;
  const i = (y * W + x) * 3;
  buf[i] = mix(buf[i], c[0], a);
  buf[i + 1] = mix(buf[i + 1], c[1], a);
  buf[i + 2] = mix(buf[i + 2], c[2], a);
}

function fillCircle(cx, cy, r, c, a = 1) {
  const x0 = Math.max(0, Math.floor(cx - r)), x1 = Math.min(W - 1, Math.ceil(cx + r));
  const y0 = Math.max(0, Math.floor(cy - r)), y1 = Math.min(W - 1, Math.ceil(cy + r));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const d = Math.hypot(x - cx, y - cy);
      const cov = clamp(r - d + 0.5, 0, 1);
      if (cov > 0) px(x, y, c, a * cov);
    }
  }
}

function ring(cx, cy, r, w, c, a) {
  const x0 = Math.max(0, Math.floor(cx - r - w)), x1 = Math.min(W - 1, Math.ceil(cx + r + w));
  const y0 = Math.max(0, Math.floor(cy - r - w)), y1 = Math.min(W - 1, Math.ceil(cy + r + w));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const d = Math.abs(Math.hypot(x - cx, y - cy) - r);
      const cov = clamp(w / 2 - d + 0.5, 0, 1);
      if (cov > 0) px(x, y, c, a * cov);
    }
  }
}

function seg(x1, y1, x2, y2, w, c, a = 1) {
  const minx = Math.floor(Math.min(x1, x2) - w), maxx = Math.ceil(Math.max(x1, x2) + w);
  const miny = Math.floor(Math.min(y1, y2) - w), maxy = Math.ceil(Math.max(y1, y2) + w);
  const vx = x2 - x1, vy = y2 - y1;
  const len2 = vx * vx + vy * vy || 1;
  for (let y = Math.max(0, miny); y <= Math.min(W - 1, maxy); y++) {
    for (let x = Math.max(0, minx); x <= Math.min(W - 1, maxx); x++) {
      let t = ((x - x1) * vx + (y - y1) * vy) / len2;
      t = clamp(t, 0, 1);
      const d = Math.hypot(x - (x1 + vx * t), y - (y1 + vy * t));
      const cov = clamp(w / 2 - d + 0.5, 0, 1);
      if (cov > 0) px(x, y, c, a * cov);
    }
  }
}

function poly(points, c, a = 1) {
  let miny = Infinity, maxy = -Infinity;
  for (const p of points) { miny = Math.min(miny, p[1]); maxy = Math.max(maxy, p[1]); }
  for (let y = Math.max(0, Math.floor(miny)); y <= Math.min(W - 1, Math.ceil(maxy)); y++) {
    const yc = y + 0.5;
    const xs = [];
    for (let i = 0; i < points.length; i++) {
      const p1 = points[i], p2 = points[(i + 1) % points.length];
      if ((p1[1] <= yc && p2[1] > yc) || (p2[1] <= yc && p1[1] > yc)) {
        const t = (yc - p1[1]) / (p2[1] - p1[1]);
        xs.push(p1[0] + t * (p2[0] - p1[0]));
      }
    }
    xs.sort((a1, b1) => a1 - b1);
    for (let i = 0; i + 1 < xs.length; i += 2) {
      const x0 = Math.max(0, Math.floor(xs[i])), x1 = Math.min(W - 1, Math.ceil(xs[i + 1]));
      for (let x = x0; x <= x1; x++) {
        const cov = clamp(Math.min(x + 1, xs[i + 1]) - Math.max(x, xs[i]) + 0.5, 0, 1);
        if (cov > 0) px(x, y, c, a * Math.min(1, cov));
      }
    }
  }
}

function roundRect(cx, cy, w, h, r, c, a = 1) {
  const x0 = Math.max(0, Math.floor(cx - w / 2)), x1 = Math.min(W - 1, Math.ceil(cx + w / 2));
  const y0 = Math.max(0, Math.floor(cy - h / 2)), y1 = Math.min(W - 1, Math.ceil(cy + h / 2));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const dx = Math.abs(x + 0.5 - cx) - (w / 2 - r);
      const dy = Math.abs(y + 0.5 - cy) - (h / 2 - r);
      const d = Math.hypot(Math.max(dx, 0), Math.max(dy, 0)) + Math.min(Math.max(dx, dy), 0) - r;
      const cov = clamp(0.5 - d, 0, 1);
      if (cov > 0) px(x, y, c, a * cov);
    }
  }
}

// background gradient + glow
for (let y = 0; y < W; y++) {
  const t = y / W;
  const base = [mix(BG_TOP[0], BG_BOT[0], t), mix(BG_TOP[1], BG_BOT[1], t), mix(BG_TOP[2], BG_BOT[2], t)];
  for (let x = 0; x < W; x++) {
    const dx = (x - W / 2) / W, dy = (y - W * 0.32) / W;
    const g = clamp(1 - Math.hypot(dx, dy) * 2.1, 0, 1);
    const i = (y * W + x) * 3;
    buf[i] = mix(base[0], GLOW[0], g * 0.55);
    buf[i + 1] = mix(base[1], GLOW[1], g * 0.55);
    buf[i + 2] = mix(base[2], GLOW[2], g * 0.55);
  }
}

// radar rings
for (const r of [0.30, 0.38, 0.46]) ring(W / 2, W / 2, W * r, W * 0.006, hex("#4C8DFF"), 0.16);
seg(W / 2, W * 0.04, W / 2, W * 0.96, W * 0.003, hex("#4C8DFF"), 0.10);
seg(W * 0.04, W / 2, W * 0.96, W / 2, W * 0.003, hex("#4C8DFF"), 0.10);

// warning triangle
const top = [W * 0.5, W * 0.19];
const left = [W * 0.14, W * 0.80];
const right = [W * 0.86, W * 0.80];
poly([top, right, left], TRI_FILL, 1);
const ow = W * 0.030;
seg(top[0], top[1], right[0], right[1], ow, ORANGE);
seg(right[0], right[1], left[0], left[1], ow, ORANGE);
seg(left[0], left[1], top[0], top[1], ow, ORANGE);
for (const p of [top, right, left]) fillCircle(p[0], p[1], ow * 0.5, ORANGE);

// --- drone glyph (left inside triangle) ---
(function drone(cx, cy, s) {
  const arm = s * 0.42;
  const lw = s * 0.075;
  seg(cx - arm, cy - arm, cx + arm, cy + arm, lw, WHITE);
  seg(cx + arm, cy - arm, cx - arm, cy + arm, lw, WHITE);
  const rr = s * 0.155;
  for (const [ox, oy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    fillCircle(cx + ox * arm, cy + oy * arm, rr, WHITE);
    fillCircle(cx + ox * arm, cy + oy * arm, rr * 0.42, TRI_FILL);
  }
  roundRect(cx, cy, s * 0.30, s * 0.20, s * 0.07, WHITE);
  fillCircle(cx, cy + s * 0.14, s * 0.045, WHITE);
})(W * 0.395, W * 0.545, W * 0.215);

// --- missile glyph (right inside triangle) ---
(function missile(cx, cy, s) {
  // body
  poly([
    [cx, cy - s * 0.62],
    [cx + s * 0.115, cy - s * 0.34],
    [cx + s * 0.115, cy + s * 0.34],
    [cx - s * 0.115, cy + s * 0.34],
    [cx - s * 0.115, cy - s * 0.34],
  ], WHITE);
  // fins
  poly([[cx - s * 0.115, cy + s * 0.10], [cx - s * 0.30, cy + s * 0.42], [cx - s * 0.115, cy + s * 0.40]], WHITE);
  poly([[cx + s * 0.115, cy + s * 0.10], [cx + s * 0.30, cy + s * 0.42], [cx + s * 0.115, cy + s * 0.40]], WHITE);
  // window band
  roundRect(cx, cy - s * 0.22, s * 0.16, s * 0.10, s * 0.03, TRI_FILL);
  // flame
  poly([[cx - s * 0.085, cy + s * 0.36], [cx, cy + s * 0.72], [cx + s * 0.085, cy + s * 0.36]], FLAME, 0.95);
  poly([[cx - s * 0.045, cy + s * 0.36], [cx, cy + s * 0.60], [cx + s * 0.045, cy + s * 0.36]], WHITE, 0.9);
})(W * 0.607, W * 0.545, W * 0.225);

// downscale
const out = Buffer.alloc(S * S * 4);
for (let y = 0; y < S; y++) {
  for (let x = 0; x < S; x++) {
    let r = 0, g = 0, b = 0;
    for (let sy = 0; sy < SS; sy++) {
      for (let sx = 0; sx < SS; sx++) {
        const i = ((y * SS + sy) * W + (x * SS + sx)) * 3;
        r += buf[i]; g += buf[i + 1]; b += buf[i + 2];
      }
    }
    const n = SS * SS;
    const o = (y * S + x) * 4;
    out[o] = Math.round(r / n);
    out[o + 1] = Math.round(g / n);
    out[o + 2] = Math.round(b / n);
    out[o + 3] = 255;
  }
}

// PNG encode
function crc32(bufIn) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < bufIn.length; n++) {
    c = (crc ^ bufIn[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td), 0);
  return Buffer.concat([len, td, crc]);
}
const raw = Buffer.alloc((S * 4 + 1) * S);
for (let y = 0; y < S; y++) {
  raw[y * (S * 4 + 1)] = 0;
  out.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const target = path.join(__dirname, "..", "AlertOrenburg", "Sources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png");
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, png);
console.log("wrote", target, png.length, "bytes");
