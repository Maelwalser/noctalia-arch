"use strict";

// Shift+click on an image copies it to the clipboard as PNG.
//
// The press and the click are intercepted in the capture phase on the window,
// so they never reach the page (no lightbox opens, no drag starts) or the
// browser (no "open link in new window"). Only a plain Shift is claimed;
// Ctrl/Alt/Meta combinations and clicks that do not land on an image behave
// as usual.

(() => {
  const TOAST_MS = 1600;
  const MAX_SIDE = 8192;

  // ── Hit testing ──────────────────────────────────────────────────────────

  function cssBackgroundUrl(el) {
    if (!(el instanceof Element)) return null;
    const tag = el.tagName;
    // A page wallpaper is never what the user meant.
    if (tag === "HTML" || tag === "BODY") return null;
    const bg = getComputedStyle(el).backgroundImage;
    const m = bg && /url\((['"]?)(.*?)\1\)/.exec(bg);
    return m ? m[2] : null;
  }

  function isDrawable(el) {
    return (
      el instanceof HTMLImageElement ||
      el instanceof HTMLCanvasElement ||
      el instanceof HTMLVideoElement ||
      el instanceof SVGSVGElement
    );
  }

  function hasOwnText(el) {
    for (const n of el.childNodes) {
      if (n.nodeType === Node.TEXT_NODE && n.nodeValue.trim()) return true;
    }
    return false;
  }

  // Walk the hit-test stack so transparent overlays and links placed on top
  // of a picture still resolve to the picture underneath. Open shadow roots
  // are searched too, since elementsFromPoint only returns their host. The
  // walk stops at an element with text of its own: a Shift+click on text is
  // a selection gesture, even when a background image sits behind it.
  function findTarget(root, x, y, depth = 0) {
    if (depth > 8 || typeof root.elementsFromPoint !== "function") return null;
    for (const el of root.elementsFromPoint(x, y)) {
      if (isDrawable(el)) return { el, kind: "element" };
      if (el.shadowRoot) {
        const inner = findTarget(el.shadowRoot, x, y, depth + 1);
        if (inner) return inner;
      }
      if (hasOwnText(el)) return null;
      const url = cssBackgroundUrl(el);
      if (url) return { el, kind: "url", url };
    }
    return null;
  }

  // ── Pixel extraction ─────────────────────────────────────────────────────

  function isTaint(err) {
    return err && err.name === "SecurityError";
  }

  function mimeOf(blob) {
    return blob.type.split(";")[0].trim();
  }

  async function drawToPng(source, width, height) {
    width = Math.round(width);
    height = Math.round(height);
    if (!(width > 0 && height > 0)) throw new Error("image has no size");
    if (width > MAX_SIDE || height > MAX_SIDE) throw new Error(`image too large (${width}×${height})`);
    const canvas = new OffscreenCanvas(width, height);
    canvas.getContext("2d").drawImage(source, 0, 0, width, height);
    // Rejects with SecurityError when the source tainted the canvas.
    return canvas.convertToBlob({ type: "image/png" });
  }

  function base64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function isSameOrigin(url) {
    try { return new URL(url, location.href).origin === location.origin; } catch { return false; }
  }

  async function fetchBlob(url) {
    // Same-origin and inline sources come straight from the page's own cache.
    // Cross-origin ones go through the worker: a content script is bound by
    // the page's CORS rules, so it could not read them anyway.
    if (url.startsWith("data:") || url.startsWith("blob:") || isSameOrigin(url)) {
      const res = await fetch(url, { credentials: "include" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return res.blob();
    }
    const res = await chrome.runtime.sendMessage({ type: "fetch-image", url });
    if (!res?.ok) throw new Error(res?.error || "could not fetch image");
    return new Blob([base64ToBytes(res.data)], { type: res.contentType });
  }

  function loadImage(blob) {
    return new Promise((resolve, reject) => {
      const objectUrl = URL.createObjectURL(blob);
      const img = new Image();
      img.onload = () => { URL.revokeObjectURL(objectUrl); resolve(img); };
      img.onerror = () => { URL.revokeObjectURL(objectUrl); reject(new Error("could not decode image")); };
      img.src = objectUrl;
    });
  }

  function isSvgUrl(url) {
    return /^data:image\/svg\+xml/i.test(url) || /\.svgz?([?#]|$)/i.test(url);
  }

  // Vector sources have no meaningful intrinsic pixel size, so rasterise them
  // at whichever is larger: the intrinsic size or the on-screen size in device
  // pixels. Otherwise a big SVG would come out as a tiny blurry bitmap.
  function vectorSize(el, naturalW, naturalH) {
    const rect = el.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    return [
      Math.min(MAX_SIDE, Math.max(naturalW, rect.width * dpr)),
      Math.min(MAX_SIDE, Math.max(naturalH, rect.height * dpr)),
    ];
  }

  async function blobToPng(blob, el) {
    const mime = mimeOf(blob);
    if (mime === "image/png") return blob;
    if (mime !== "image/svg+xml") {
      try {
        const bmp = await createImageBitmap(blob);
        try { return await drawToPng(bmp, bmp.width, bmp.height); } finally { bmp.close(); }
      } catch {
        // Not decodable by createImageBitmap; try the <img> decoder below.
      }
    }
    const img = await loadImage(blob);
    const size = mime === "image/svg+xml"
      ? vectorSize(el, img.naturalWidth, img.naturalHeight)
      : [img.naturalWidth, img.naturalHeight];
    return drawToPng(img, ...size);
  }

  async function pngFromTarget(target) {
    const { el } = target;
    if (target.kind === "url") return blobToPng(await fetchBlob(target.url), el);

    if (el instanceof HTMLCanvasElement) return drawToPng(el, el.width, el.height);

    if (el instanceof HTMLVideoElement) {
      if (el.readyState < 2) throw new Error("video has no frame yet");
      return drawToPng(el, el.videoWidth, el.videoHeight);
    }

    if (el instanceof SVGSVGElement) {
      const svg = new XMLSerializer().serializeToString(el);
      return blobToPng(new Blob([svg], { type: "image/svg+xml" }), el);
    }

    const url = el.currentSrc || el.src;
    if (!url) throw new Error("image has no source");
    if (el.complete && el.naturalWidth > 0) {
      // Fast path: the decoded image is already in memory.
      try {
        const [w, h] = isSvgUrl(url)
          ? vectorSize(el, el.naturalWidth, el.naturalHeight)
          : [el.naturalWidth, el.naturalHeight];
        return await drawToPng(el, w, h);
      } catch (err) {
        if (!isTaint(err)) throw err;
      }
    }
    return blobToPng(await fetchBlob(url), el);
  }

  // ── Clipboard ────────────────────────────────────────────────────────────

  function blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result).split(",", 2)[1]);
      r.onerror = () => reject(r.error);
      r.readAsDataURL(blob);
    });
  }

  async function writeToClipboard(blob) {
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
      return;
    } catch (err) {
      // Cross-origin frames are usually denied clipboard-write by permissions
      // policy. The user activation propagates to the top frame, so let the
      // worker hand the bytes to the top-frame content script instead.
      if (window === window.top) throw err;
      const res = await chrome.runtime.sendMessage({
        type: "relay-clipboard",
        data: await blobToBase64(blob),
      });
      if (!res?.ok) throw new Error(res?.error || err.message);
    }
  }

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg?.type !== "write-clipboard" || window !== window.top) return false;
    const blob = new Blob([base64ToBytes(msg.data)], { type: "image/png" });
    navigator.clipboard
      .write([new ClipboardItem({ "image/png": blob })])
      .then(() => sendResponse({ ok: true }), (e) => sendResponse({ ok: false, error: String(e?.message || e) }));
    return true;
  });

  // ── Feedback ─────────────────────────────────────────────────────────────

  let host = null;
  function ensureHost() {
    if (host && host.isConnected) return host.shadowRoot;
    host = document.createElement("shift-copy-image-ui");
    const root = host.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>
        :host { all: initial; position: fixed; inset: 0; pointer-events: none; z-index: 2147483647; }
        .flash {
          position: fixed; box-sizing: border-box;
          outline: 2px solid #b4ff39; outline-offset: -2px;
          background: rgba(180, 255, 57, 0.18);
          animation: fade ${TOAST_MS}ms ease-out forwards;
        }
        .toast {
          position: fixed; right: 16px; bottom: 16px; max-width: 60vw;
          padding: 6px 10px; border-radius: 4px;
          font: 12px/1.4 ui-monospace, "JetBrains Mono", monospace;
          color: #e8ffd0; background: rgba(12, 16, 10, 0.92);
          border-left: 3px solid #b4ff39;
          white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
          animation: fade ${TOAST_MS}ms ease-out forwards;
        }
        .toast.error { color: #ffd6d6; border-left-color: #ff5a5a; }
        @keyframes fade { 0%, 60% { opacity: 1; } 100% { opacity: 0; } }
      </style>`;
    (document.documentElement || document).appendChild(host);
    return root;
  }

  function notify(text, { el = null, error = false } = {}) {
    const root = ensureHost();
    for (const old of root.querySelectorAll(".toast, .flash")) old.remove();
    if (el) {
      const r = el.getBoundingClientRect();
      const flash = document.createElement("div");
      flash.className = "flash";
      Object.assign(flash.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      root.appendChild(flash);
    }
    const toast = document.createElement("div");
    toast.className = error ? "toast error" : "toast";
    toast.textContent = text;
    root.appendChild(toast);
    setTimeout(() => { toast.remove(); root.querySelector(".flash")?.remove(); }, TOAST_MS);
  }

  // ── Event wiring ─────────────────────────────────────────────────────────

  // The target claimed at press time. The matching release and click are
  // swallowed whatever the modifier state is by then, so the page never sees
  // half of a gesture.
  let armed = null;

  function targetFor(e) {
    const plainShift = e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey;
    return e.isTrusted && e.button === 0 && plainShift
      ? findTarget(document, e.clientX, e.clientY)
      : null;
  }

  function swallow(e) {
    e.preventDefault();
    e.stopImmediatePropagation();
  }

  for (const type of ["pointerdown", "mousedown"]) {
    window.addEventListener(type, (e) => {
      if (!e.isTrusted) return;
      if (type === "pointerdown") armed = null;
      armed = targetFor(e) || armed;
      if (armed) swallow(e);
    }, true);
  }

  for (const type of ["pointerup", "mouseup"]) {
    window.addEventListener(type, (e) => {
      if (e.isTrusted && armed) swallow(e);
    }, true);
  }

  window.addEventListener("click", async (e) => {
    if (!e.isTrusted) return;
    const target = armed || targetFor(e);
    armed = null;
    if (!target) return;
    swallow(e);
    try {
      const png = await pngFromTarget(target);
      const bmp = await createImageBitmap(png);
      const size = `${bmp.width}×${bmp.height}`;
      bmp.close();
      await writeToClipboard(png);
      notify(`Copied image ${size}`, { el: target.el });
    } catch (err) {
      notify(`Copy failed: ${err?.message || err}`, { el: target.el, error: true });
    }
  }, true);
})();
