"use strict";

// Content scripts are bound by the page's CORS rules, so they cannot read the
// bytes of most cross-origin images. The service worker has host permissions
// for every URL and can. It also relays clipboard writes from frames that are
// not allowed to use the clipboard themselves to the top frame of the tab.

// runtime messages are capped at 64 MiB and base64 adds a third, so stay well below.
const MAX_BYTES = 32 * 1024 * 1024;

function bytesToBase64(bytes) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

async function fetchImage(url) {
  // The URL comes from page-controlled markup (img src, CSS backgrounds), so
  // only ordinary web schemes are fetched on the user's behalf.
  const parsed = new URL(url);
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`unsupported URL scheme ${parsed.protocol}`);
  }
  const res = await fetch(parsed, { credentials: "include" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const declared = Number(res.headers.get("content-length"));
  if (declared > MAX_BYTES) throw new Error("image too large");
  const buf = await res.arrayBuffer();
  if (buf.byteLength > MAX_BYTES) throw new Error("image too large");
  return {
    ok: true,
    contentType: res.headers.get("content-type") || "",
    data: bytesToBase64(new Uint8Array(buf)),
  };
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const fail = (err) => sendResponse({ ok: false, error: String(err?.message || err) });
  // Only this extension's own content scripts, running in a tab, are served.
  if (sender.id !== chrome.runtime.id || !sender.tab?.id) return false;
  switch (msg?.type) {
    case "fetch-image":
      fetchImage(msg.url).then(sendResponse, fail);
      return true;
    case "relay-clipboard":
      if (typeof msg.data !== "string" || msg.data.length > MAX_BYTES * 2) { fail("bad payload"); return false; }
      chrome.tabs
        .sendMessage(sender.tab.id, { type: "write-clipboard", data: msg.data }, { frameId: 0 })
        .then(sendResponse, fail);
      return true;
    default:
      return false;
  }
});
