// Iron Horizon start-up diagnostics.
//
// Loaded from the page <head> (export preset html/head_include) before the engine.
// If the game fails to start it shows a readable panel with the reason and device
// details instead of a silent black screen. Players can screenshot it or tap
// "Copy details". Add ?diag=1 to the URL to show the panel even when the game works.
(function () {
  "use strict";
  var errors = [];
  var shown = false;
  var params = new URLSearchParams(location.search);
  var STARTING_KEY = "ih_starting_since";

  // --- Capability probes -------------------------------------------------
  function validate(bytes) {
    try { return WebAssembly.validate(new Uint8Array(bytes)); } catch (e) { return false; }
  }
  // Godot 4.7's official web build uses WebAssembly SIMD (Safari / iOS 16.4+)
  // and exception handling (Safari / iOS 15.2+).
  var hasWasm = typeof WebAssembly === "object";
  var hasSimd = hasWasm && validate([0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11]);
  var hasEh = hasWasm && validate([0,97,115,109,1,0,0,0,1,4,1,96,0,0,3,2,1,0,10,8,1,6,0,6,64,25,11,11]);
  var hasWebGL2 = (function () {
    try { var c = document.createElement("canvas"); return !!c.getContext("webgl2"); } catch (e) { return false; }
  })();

  var ua = navigator.userAgent;
  var iosMatch = ua.match(/OS (\d+)[_.](\d+)(?:[_.](\d+))? like Mac OS X/);
  // iPadOS 13+ reports itself as a Mac; touch points give it away
  var isIPadDesktopUA = /Macintosh/.test(ua) && navigator.maxTouchPoints > 1;
  var isApple = !!iosMatch || isIPadDesktopUA;
  var safariVer = (ua.match(/Version\/(\d+(?:\.\d+)?)/) || [])[1];
  var iosVersion = iosMatch ? iosMatch[1] + "." + iosMatch[2] + (iosMatch[3] ? "." + iosMatch[3] : "")
                            : (isIPadDesktopUA && safariVer ? "iPadOS (Safari " + safariVer + ")" : null);

  function details() {
    return [
      "Device: " + (iosVersion ? (isIPadDesktopUA ? "iPad, " : "iPhone/iPad, iOS ") + iosVersion : navigator.platform),
      "Browser: " + ua,
      "Screen: " + screen.width + "x" + screen.height + " @" + (window.devicePixelRatio || 1) + "x",
      "WebAssembly: " + hasWasm + ", SIMD: " + hasSimd + ", exceptions: " + hasEh + ", WebGL 2: " + hasWebGL2,
      "Memory hint: " + (navigator.deviceMemory ? navigator.deviceMemory + " GB" : "n/a"),
      "Page: " + location.href,
    ].concat(errors.length ? ["", "Errors:"].concat(errors.slice(-12)) : []).join("\n");
  }

  // --- Panel ---------------------------------------------------------------
  function showPanel(title, message) {
    if (shown) return;
    shown = true;
    var build = function () {
      var p = document.createElement("div");
      p.id = "ih-diag";
      p.setAttribute("style", "position:fixed;inset:0;z-index:2147483647;overflow:auto;background:rgba(10,16,11,0.97);color:#d9f2d0;font:15px/1.45 -apple-system,system-ui,sans-serif;padding:max(18px,env(safe-area-inset-top)) 18px 18px;-webkit-user-select:text;user-select:text;touch-action:auto");
      var h = document.createElement("h2");
      h.textContent = title;
      h.setAttribute("style", "margin:0 0 10px;color:#9dff7a;font-size:20px");
      var m = document.createElement("p");
      m.textContent = message;
      m.setAttribute("style", "margin:0 0 14px;white-space:pre-line");
      var pre = document.createElement("pre");
      pre.textContent = details();
      pre.setAttribute("style", "white-space:pre-wrap;word-break:break-word;background:#050a06;border:1px solid #3b6b2c;border-radius:6px;padding:10px;font:12px/1.4 ui-monospace,Menlo,monospace;color:#b8d9ae;margin:0 0 14px");
      var btns = document.createElement("div");
      var mk = function (label, fn) {
        var b = document.createElement("button");
        b.textContent = label;
        b.setAttribute("style", "font:inherit;margin:0 10px 10px 0;padding:10px 16px;border-radius:6px;border:1px solid #5fbf45;background:#1d3a17;color:#d9f2d0");
        b.onclick = fn;
        btns.appendChild(b);
      };
      mk("Copy details", function () {
        var txt = title + "\n" + message + "\n\n" + details();
        if (navigator.clipboard) navigator.clipboard.writeText(txt).then(function () { pre.textContent = details() + "\n\n(copied)"; });
      });
      mk("Try again", function () { sessionStorage.removeItem(STARTING_KEY); location.reload(); });
      mk("Close", function () { p.remove(); });
      p.appendChild(h); p.appendChild(m); p.appendChild(btns); p.appendChild(pre);
      document.body.appendChild(p);
    };
    if (document.body) build(); else document.addEventListener("DOMContentLoaded", build);
  }

  // --- Error capture ---------------------------------------------------------
  function record(msg) {
    msg = String(msg).slice(0, 400);
    if (errors.indexOf(msg) === -1) errors.push(msg);
    var pre = document.querySelector("#ih-diag pre");
    if (pre) pre.textContent = details();
    if (/CompileError|LinkError|RuntimeError|Aborted|abort\(|out of memory|OOM|Cannot enlarge memory|WebAssembly\.(instantiate|Memory)/i.test(msg)) {
      showPanel("The game crashed while starting", explain());
    }
  }
  window.addEventListener("error", function (e) { record((e.message || "error") + (e.filename ? " (" + e.filename.split("/").pop() + ":" + e.lineno + ")" : "")); });
  window.addEventListener("unhandledrejection", function (e) { var r = e.reason; record("Unhandled: " + (r && (r.stack || r.message) || r)); });
  var origError = console.error;
  console.error = function () {
    try { record(Array.prototype.map.call(arguments, function (a) { return a && a.message ? a.message : String(a); }).join(" ")); } catch (e) {}
    return origError.apply(console, arguments);
  };
  document.addEventListener("webglcontextlost", function () {
    record("WebGL context lost (graphics memory exhausted or GPU reset)");
    showPanel("Graphics stopped working", "The browser took away the game's graphics context, usually because the device ran out of graphics memory. Close other tabs and apps, then tap Try again.");
  }, true);

  function explain() {
    if (!hasWasm) return "This browser does not support WebAssembly, which the game needs.";
    if (!hasWebGL2) return "This browser has WebGL 2 turned off or unsupported. The game needs WebGL 2 (iOS 15+ / any current Chrome, Edge, Firefox or Safari).";
    if (!hasSimd || !hasEh) {
      return isApple
        ? "This iPhone/iPad's software is too old for the game. It needs iOS / iPadOS 16.4 or newer (Settings → General → Software Update). All iPhone browsers use Safari's engine, so switching to Chrome won't help — updating iOS will."
        : "This browser is too old for the game (it lacks WebAssembly SIMD). Please update your browser.";
    }
    return "Something went wrong while the game was starting. Please screenshot this panel (or tap Copy details) and send it to the developer.";
  }

  // --- Up-front checks -------------------------------------------------------
  if (!hasWasm || !hasSimd || !hasEh || !hasWebGL2) {
    showPanel(isApple && hasWasm && hasWebGL2 ? "Please update iOS to play" : "This browser can't run the game", explain());
  }

  // The game sets window.__ihStarted from game_manager.gd once its scene is up.
  window.__ihGameStarted = function () {
    window.__ihStarted = true;
    try { sessionStorage.removeItem(STARTING_KEY); } catch (e) {}
    if (params.has("diag")) showPanel("Diagnostics (game started OK)", "The game started normally on this device.");
  };

  // If the previous load of this tab never finished starting, iOS most likely
  // killed the tab (out of memory) and reloaded it.
  try {
    var prev = sessionStorage.getItem(STARTING_KEY);
    if (prev && Date.now() - Number(prev) < 5 * 60 * 1000) {
      record("Previous attempt " + Math.round((Date.now() - Number(prev)) / 1000) + " s ago never finished starting (tab was reloaded)");
      showPanel("The game crashed while starting", "The browser reloaded the page before the game could start. On iPhones this usually means it ran out of memory. Close other tabs and apps (or restart the phone), then tap Try again.");
    }
    sessionStorage.setItem(STARTING_KEY, String(Date.now()));
  } catch (e) {}

  // Watchdog: the download finished but the game never started. Never fires while
  // still downloading (40 MB can take minutes on mobile data).
  var doneSince = 0;
  var timer = setInterval(function () {
    if (window.__ihStarted || shown) { clearInterval(timer); return; }
    var status = document.getElementById("status");
    var notice = document.getElementById("status-notice");
    var bar = document.getElementById("status-progress");
    if (notice && notice.style.display === "block") {
      // Godot's own loader reported a failure; its message is in the notice
      record("Loader: " + notice.textContent);
      clearInterval(timer);
      showPanel("The game couldn't start", explain());
      return;
    }
    var downloaded = !status || (bar && bar.max > 0 && bar.value >= bar.max);
    if (downloaded && !doneSince) doneSince = Date.now();
    // Engine removed the loading screen (or bar is full) yet the game never reported in
    if (doneSince && Date.now() - doneSince > (status ? 30000 : 15000)) {
      clearInterval(timer);
      record("Download finished " + Math.round((Date.now() - doneSince) / 1000) + " s ago but the game never started");
      showPanel("The game didn't start", explain());
    }
  }, 1000);
})();
