// Checks web/diag.js on the live site: silent on a normal start, explains failures.
import { webkit, chromium, devices } from "playwright";
import fs from "node:fs";
const BASE = "https://marse337.github.io/iron-horizon/";
fs.mkdirSync("results/diag", { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function run(name, engine, device, url, initScript) {
  const browser = await engine.launch(engine === chromium ? { channel: "chrome", args: ["--enable-unsafe-swiftshader"] } : {});
  const ctx = await browser.newContext({ ...devices[device] });
  if (initScript) await ctx.addInitScript(initScript);
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: "domcontentloaded" });
  let r;
  for (let i = 0; i < 90; i++) {
    await sleep(1000);
    r = await page.evaluate(() => ({ started: !!window.__ihStarted, panel: document.querySelector("#ih-diag h2")?.textContent || null, msg: document.querySelector("#ih-diag p")?.textContent || null }));
    if (r.panel || (r.started && !url.includes("diag=1"))) break;
  }
  await sleep(800);
  await page.screenshot({ path: `results/diag/${name}.png` });
  console.log(name.padEnd(22), JSON.stringify(r));
  await browser.close();
  return r;
}

const normal = await run("normal-iphone", webkit, "iPhone 14 landscape", BASE);
const normalChrome = await run("normal-android-chrome", chromium, "Pixel 7 landscape", BASE);
const diag = await run("diag-param", webkit, "iPhone 14 landscape", BASE + "?diag=1");
// Simulate an iPhone on iOS < 16.4: Safari without WebAssembly SIMD
const oldIos = await run("old-ios-no-simd", webkit, "iPhone 14 landscape", BASE, () => {
  const v = WebAssembly.validate.bind(WebAssembly);
  WebAssembly.validate = (bytes) => { const b = new Uint8Array(bytes); return b.includes(253) && b.length < 64 ? false : v(bytes); };
  WebAssembly.instantiate = () => Promise.reject(new WebAssembly.CompileError("WebAssembly.instantiate(): Compiling function failed: invalid opcode 0xfd"));
  WebAssembly.instantiateStreaming = WebAssembly.instantiate;
});
const ok = normal.started && !normal.panel && normalChrome.started && !normalChrome.panel && diag.panel && /started OK/.test(diag.panel) && /update iOS/i.test(oldIos.panel || "");
console.log(ok ? "ALL GOOD" : "CHECK FAILED");
