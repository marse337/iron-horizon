// Touch-control regression test for the Iron Horizon web build.
//
//   node touch-test.mjs <target> [url]
//
// targets:
//   chrome-phone   Desktop Chrome emulating a Pixel 7 (landscape), real CDP multi-touch
//   chrome-tablet  Desktop Chrome emulating a Galaxy Tab S4 (landscape)
//   webkit-iphone  Playwright WebKit (Safari's engine), iPhone 14 profile (landscape)
//   webkit-ipad    Playwright WebKit, iPad Pro 11 profile (landscape)
//   android        Chrome inside a running Android emulator (adb + DevTools)
//
// The page is opened with ?test=1 so the game publishes its state to window.__ih
// (see _publish_test_state in scripts/game_manager.gd). Screenshots and a JSON
// report go to results/<target>/.

import { chromium, webkit, devices } from "playwright";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const TARGET = process.argv[2] || "chrome-phone";
const BASE_URL = process.argv[3] || "https://marse337.github.io/iron-horizon/";
const PAGE_URL = BASE_URL + (BASE_URL.includes("?") ? "&" : "?") + "test=1";
const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), "results", TARGET);
fs.mkdirSync(OUT, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
let shotN = 0;

function check(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`);
}

// ---------------------------------------------------------------------------
// Touch drivers. Both keep the set of fingers currently down and send events
// that mirror what a real touchscreen produces.
// ---------------------------------------------------------------------------

/** Chromium: DevTools Input.dispatchTouchEvent — trusted, goes through Chrome's real input pipeline. */
class CdpTouch {
  constructor(cdp) { this.cdp = cdp; this.active = new Map(); }
  #points() { return [...this.active.entries()].map(([id, p]) => ({ x: p.x, y: p.y, id, radiusX: 8, radiusY: 8, force: 1 })); }
  async down(id, x, y) { this.active.set(id, { x, y }); await this.cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: this.#points() }); }
  async move(id, x, y) { this.active.set(id, { x, y }); await this.cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: this.#points() }); }
  async up(id) { this.active.delete(id); await this.cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: this.#points() }); }
}

/** WebKit (no CDP): dispatch DOM TouchEvents on the canvas, the same events Godot's web layer listens to. */
class DomTouch {
  constructor(page) { this.page = page; this.active = new Map(); }
  async #send(type, changedId) {
    const all = [...this.active.entries()].map(([id, p]) => ({ id, ...p }));
    await this.page.evaluate(({ type, all, changedId, changedPos }) => {
      const canvas = document.querySelector("canvas");
      // WebKit rejects `new Touch(...)` from script; its legacy createTouch API works
      const mk = (t) => document.createTouch(window, canvas, t.id, t.x, t.y, t.x, t.y);
      const touches = document.createTouchList(...all.map(mk));
      const changed = document.createTouchList(mk({ id: changedId, ...changedPos }));
      canvas.dispatchEvent(new TouchEvent(type, { touches, targetTouches: touches, changedTouches: changed, bubbles: true, cancelable: true }));
    }, { type, all, changedId, changedPos: this.last });
  }
  async down(id, x, y) { this.active.set(id, { x, y }); this.last = { x, y }; await this.#send("touchstart", id); }
  async move(id, x, y) { this.active.set(id, { x, y }); this.last = { x, y }; await this.#send("touchmove", id); }
  async up(id) { this.last = this.active.get(id); this.active.delete(id); await this.#send("touchend", id); }
}

// ---------------------------------------------------------------------------

async function openTarget() {
  const landscape = (name) => devices[name];
  switch (TARGET) {
    case "chrome-phone":
    case "chrome-tablet": {
      const browser = await chromium.launch({
        channel: "chrome", headless: true,
        args: ["--ignore-gpu-blocklist", "--enable-gpu", "--use-angle=d3d11", "--enable-unsafe-swiftshader"],
      });
      const ctx = await browser.newContext({ ...landscape(TARGET === "chrome-phone" ? "Pixel 7 landscape" : "Galaxy Tab S4 landscape") });
      const page = await ctx.newPage();
      const cdp = await ctx.newCDPSession(page);
      return { browser, ctx, page, touch: new CdpTouch(cdp), canRotate: true };
    }
    case "webkit-iphone":
    case "webkit-ipad": {
      const browser = await webkit.launch({ headless: true });
      const ctx = await browser.newContext({ ...landscape(TARGET === "webkit-iphone" ? "iPhone 14 landscape" : "iPad Pro 11 landscape") });
      const page = await ctx.newPage();
      return { browser, ctx, page, touch: new DomTouch(page), canRotate: true };
    }
    case "android": {
      const adb = path.join(process.env.LOCALAPPDATA, "Android", "Sdk", "platform-tools", "adb.exe");
      execFileSync(adb, ["forward", "tcp:9333", "localabstract:chrome_devtools_remote"]);
      const browser = await chromium.connectOverCDP("http://127.0.0.1:9333");
      const ctx = browser.contexts()[0];
      const page = ctx.pages().find((p) => p.url().includes("iron-horizon")) || ctx.pages()[0] || (await ctx.newPage());
      await page.bringToFront();
      const cdp = await ctx.newCDPSession(page);
      // Always test the latest deploy: Android Chrome otherwise reuses its cached
      // index.pck (setCacheDisabled alone didn't stop that over remote debugging)
      await cdp.send("Network.enable");
      await cdp.send("Network.clearBrowserCache");
      await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
      return { browser, ctx, page, touch: new CdpTouch(cdp), canRotate: false, adb };
    }
    default:
      throw new Error("unknown target " + TARGET);
  }
}

async function main() {
  const t = await openTarget();
  const { page, touch } = t;
  console.log(`== ${TARGET}: ${PAGE_URL}`);
  await page.goto(PAGE_URL, { waitUntil: "domcontentloaded", timeout: 120000 });

  // Canvas px -> CSS px (Godot sizes the canvas in device pixels)
  const geom = async () => page.evaluate(() => {
    const c = document.querySelector("canvas"); const r = c.getBoundingClientRect();
    return { left: r.left, top: r.top, sx: r.width / c.width, sy: r.height / c.height, dpr: window.devicePixelRatio, w: r.width, h: r.height };
  });
  const state = async () => page.evaluate(() => window.__ih || null);
  const toCss = (g, p) => ({ x: g.left + p[0] * g.sx, y: g.top + p[1] * g.sy });
  const shot = async (label) => { shotN++; await page.screenshot({ path: path.join(OUT, `${String(shotN).padStart(2, "0")}-${label}.png`) }); };
  async function waitFor(pred, ms, label) {
    const end = Date.now() + ms;
    while (Date.now() < end) { const s = await state(); if (s && pred(s)) return s; await sleep(150); }
    throw new Error("timeout waiting for " + label);
  }
  async function tap(x, y, id = 90) { await touch.down(id, x, y); await sleep(80); await touch.up(id); }
  async function drag(id, x0, y0, dx, dy, steps = 8, stepMs = 40) {
    for (let i = 1; i <= steps; i++) { await touch.move(id, x0 + (dx * i) / steps, y0 + (dy * i) / steps); await sleep(stepMs); }
  }
  const yawPerCssPx = (s, g) => s.sens / (s.canvas_per_logical * g.sx);
  const angDiff = (a, b) => { let d = a - b; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; };

  // 1. Load
  const t0 = Date.now();
  let s = await waitFor((s) => s.state === "TITLE" && s.menu_buttons.start, 180000, "game to load");
  check("game loads and reaches title screen", true, `${((Date.now() - t0) / 1000).toFixed(1)} s`);
  // Guard against testing a stale cached build: the game data must match the server's
  const pck = await page.evaluate(async () => {
    const e = performance.getEntriesByType("resource").find((r) => /index\.pck/.test(r.name));
    const fresh = await fetch("index.pck", { cache: "no-store" }).then((r) => r.arrayBuffer());
    return { loaded: e ? e.decodedBodySize : -1, server: fresh.byteLength };
  });
  check("tested build is the latest deploy (not a cached copy)", pck.loaded === pck.server, `index.pck ${pck.loaded} B loaded, server has ${pck.server} B`);
  let g = await geom();
  await shot("title");

  // 2. Tap START with a finger (menus must work with touch)
  const start = toCss(g, s.menu_buttons.start);
  await tap(start.x, start.y);
  s = await waitFor((s) => s.state === "PLAYING", 8000, "PLAYING after tapping start").catch(() => null);
  check("tapping START begins the wave", !!s);
  if (!s) return finish(t);
  check("touch controls switch on after first touch", s.touch_mode === true);
  await sleep(1500);
  s = await state(); g = await geom();
  await shot("playing-touch-ui");
  const k = yawPerCssPx(s, g);
  const B = Object.fromEntries(Object.entries(s.buttons).map(([id, b]) => [id, toCss(g, b)]));
  const aim0 = { x: g.left + g.w * 0.30, y: g.top + g.h * 0.45 };

  // 3. One-finger aim drag must turn the view and NOT fire
  let before = await state();
  await touch.down(1, aim0.x, aim0.y); await sleep(60);
  await drag(1, aim0.x, aim0.y, 120, 0);
  await touch.up(1); await sleep(250);
  let after = await state();
  let dYaw = -angDiff(after.yaw, before.yaw), want = 120 * k;
  check("aim drag turns the turret by the dragged distance", Math.abs(dYaw - want) < want * 0.2, `Δyaw ${dYaw.toFixed(3)} rad, expected ${want.toFixed(3)}`);
  check("aim drag does not fire", after.mg === before.mg, `MG ammo ${before.mg} → ${after.mg}`);

  // 4. Hold FIRE: gun fires, view must not move
  before = await state();
  await touch.down(2, B.fire.x, B.fire.y); await sleep(1200);
  after = await state();
  check("holding FIRE fires the gun", after.mg < before.mg - 2, `MG ammo ${before.mg} → ${after.mg}`);
  check("holding FIRE does not move the view", Math.abs(angDiff(after.yaw, before.yaw)) < 0.005, `Δyaw ${angDiff(after.yaw, before.yaw).toFixed(4)}`);
  await shot("holding-fire");

  // 5. Aim with a second finger while FIRE is held, with the FIRE thumb wobbling
  //    (this is the exact pattern that made the view jump before the fix)
  before = await state();
  const aim1 = { x: g.left + g.w * 0.35, y: g.top + g.h * 0.5 };
  await touch.down(3, aim1.x, aim1.y); await sleep(60);
  for (let i = 1; i <= 10; i++) {
    await touch.move(3, aim1.x - (100 * i) / 10, aim1.y);
    await touch.move(2, B.fire.x + (i % 2 ? 3 : -2), B.fire.y + (i % 2 ? -2 : 2));
    await sleep(40);
  }
  await sleep(200);
  after = await state();
  dYaw = angDiff(after.yaw, before.yaw); want = 100 * k;
  check("aiming while holding FIRE tracks the finger (no jump)", Math.abs(dYaw - want) < want * 0.2, `Δyaw ${dYaw.toFixed(3)} rad, expected ${want.toFixed(3)}`);
  check("gun keeps firing while aiming", after.mg < before.mg, `MG ammo ${before.mg} → ${after.mg}`);
  await shot("aim-while-firing");
  await touch.up(3); await touch.up(2); await sleep(300);

  // 6. Quick FIRE taps (the originally reported bug: view snapped away on tap)
  before = await state();
  for (let i = 0; i < 4; i++) { await tap(B.fire.x, B.fire.y, 10 + i); await sleep(300); }
  await sleep(900); // past the window where browsers send imitation mouse events
  after = await state();
  check("tapping FIRE repeatedly never moves the view", Math.abs(angDiff(after.yaw, before.yaw)) < 0.005, `Δyaw ${angDiff(after.yaw, before.yaw).toFixed(4)}`);
  check("every quick FIRE tap fires", before.mg - after.mg >= 4, `MG ammo ${before.mg} → ${after.mg} for 4 taps`);
  check("no stuck mouse-fire after taps", after.mouse_fire_held === false && after.fire_held === false);

  // 7. SWAP / FLARE / SAM buttons
  before = await state();
  await tap(B.swap.x, B.swap.y); await sleep(400);
  after = await state();
  check("SWAP changes weapon", after.weapon !== before.weapon, `weapon ${before.weapon} → ${after.weapon}`);
  // The cannon is fired with single taps, so a quick tap must always shoot
  before = await state();
  await touch.down(20, B.fire.x, B.fire.y); await touch.up(20); await sleep(500);
  after = await state();
  check("instant tap fires the cannon", after.cannon === before.cannon - 1, `shells ${before.cannon} → ${after.cannon}`);
  await sleep(1300); // cannon reload
  await tap(B.swap.x, B.swap.y); await sleep(300);
  before = await state();
  await tap(B.flare.x, B.flare.y); await sleep(500);
  after = await state();
  check("FLARE launches a flare", after.flare === before.flare - 1, `flares ${before.flare} → ${after.flare}`);
  before = await state();
  await tap(B.sam.x, B.sam.y); await sleep(500);
  after = await state();
  check("SAM tap does not move the view", Math.abs(angDiff(after.yaw, before.yaw)) < 0.005);

  // 7b. Android only: real touchscreen input through the emulator (adb input),
  //     i.e. the same MotionEvent -> Chrome path a finger takes, including the
  //     imitation mouse events Chrome generates after a tap.
  if (t.adb) {
    const adb = (...a) => execFileSync(t.adb, ["shell", "input", ...a.map(String)]);
    await page.evaluate(() => {
      window.__lastTouch = null;
      window.addEventListener("touchstart", (e) => { const c = e.changedTouches[0]; window.__lastTouch = [c.clientX, c.clientY]; }, { capture: true, passive: true });
    });
    // Calibrate screen px -> CSS px with two taps in the aim area (harmless)
    const vp = await page.evaluate(() => [innerWidth, innerHeight]);
    const cal = [];
    for (const [sx, sy] of [[900, 500], [1500, 750]]) {
      adb("tap", sx, sy); await sleep(500);
      cal.push({ s: [sx, sy], c: await page.evaluate(() => window.__lastTouch) });
    }
    const ok = cal.every((p) => p.c);
    check("android: real screen taps reach the game", ok, ok ? `screen ${cal[0].s} → css ${cal[0].c.map((v) => v.toFixed(0))}` : "no touchstart seen");
    if (ok) {
      const scale = (cal[1].s[0] - cal[0].s[0]) / (cal[1].c[0] - cal[0].c[0]);
      const toScreen = (p) => [Math.round(cal[0].s[0] + (p.x - cal[0].c[0]) * scale), Math.round(cal[0].s[1] + (p.y - cal[0].c[1]) * scale)];
      await sleep(900);
      // Real finger swipe to aim
      before = await state();
      const a = toScreen({ x: g.left + g.w * 0.3, y: g.top + g.h * 0.5 });
      adb("swipe", a[0], a[1], a[0] + Math.round(150 * scale), a[1], 600); await sleep(1000);
      after = await state();
      dYaw = -angDiff(after.yaw, before.yaw); want = 150 * k;
      check("android: real swipe aims (no fire)", Math.abs(dYaw - want) < want * 0.25 && after.mg === before.mg, `Δyaw ${dYaw.toFixed(3)} expected ≈${want.toFixed(3)}, MG ${before.mg} → ${after.mg}`);
      // Real finger taps on FIRE — the originally reported bug
      before = await state();
      const f = toScreen(B.fire);
      for (let i = 0; i < 4; i++) { adb("tap", f[0], f[1]); await sleep(350); }
      await sleep(1000);
      after = await state();
      check("android: real FIRE taps fire without moving the view", Math.abs(angDiff(after.yaw, before.yaw)) < 0.005 && after.mg < before.mg, `Δyaw ${angDiff(after.yaw, before.yaw).toFixed(4)}, MG ${before.mg} → ${after.mg}`);
      // Long-press FIRE with a real finger
      before = await state();
      adb("swipe", f[0], f[1], f[0] + 2, f[1] + 2, 1500); await sleep(600);
      after = await state();
      check("android: real long-press FIRE fires steadily, view still", after.mg < before.mg - 5 && Math.abs(angDiff(after.yaw, before.yaw)) < 0.01, `MG ${before.mg} → ${after.mg}, Δyaw ${angDiff(after.yaw, before.yaw).toFixed(4)}`);
      await shot("android-real-touch");
    }
  }

  // 8. Pause and resume by touch
  await tap(B.pause.x, B.pause.y);
  s = await waitFor((s) => s.state === "PAUSED" && s.menu_buttons.resume, 4000, "PAUSED").catch(() => null);
  check("pause button pauses", !!s);
  if (s) {
    await shot("paused");
    const r = toCss(g, s.menu_buttons.resume);
    await tap(r.x, r.y);
    s = await waitFor((s) => s.state === "PLAYING", 4000, "resume").catch(() => null);
    check("RESUME button works by touch", !!s);
  }

  // 9. Portrait shows the rotate prompt
  if (t.canRotate) {
    const vs = page.viewportSize();
    await page.setViewportSize({ width: vs.height, height: vs.width });
    s = await waitFor((s) => s.portrait === true, 5000, "portrait").catch(() => null);
    check("portrait shows rotate-device prompt", !!s);
    await sleep(500); await shot("portrait");
    await page.setViewportSize(vs);
  } else if (t.adb) {
    execFileSync(t.adb, ["shell", "settings", "put", "system", "accelerometer_rotation", "0"]);
    execFileSync(t.adb, ["shell", "settings", "put", "system", "user_rotation", "0"]); // portrait
    s = await waitFor((s) => s.portrait === true, 8000, "portrait").catch(() => null);
    check("portrait shows rotate-device prompt", !!s);
    await sleep(800); await shot("portrait");
    execFileSync(t.adb, ["shell", "settings", "put", "system", "user_rotation", "1"]); // landscape
  }

  await finish(t);
}

async function finish(t) {
  const failed = results.filter((r) => !r.ok).length;
  fs.writeFileSync(path.join(OUT, "report.json"), JSON.stringify({ target: TARGET, url: PAGE_URL, results }, null, 2));
  console.log(`== ${TARGET}: ${results.length - failed}/${results.length} passed  (screenshots: ${OUT})`);
  if (TARGET === "android") await t.browser.close().catch(() => {}); else await t.browser.close();
  process.exitCode = failed ? 1 : 0;
}

main().catch((e) => { console.error("ERROR", e.message); process.exitCode = 2; });
