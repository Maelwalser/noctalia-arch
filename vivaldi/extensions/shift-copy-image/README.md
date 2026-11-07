# Shift-Click Copy Image

Shift+click any image in a web page to copy it to the clipboard as PNG.
Works for `<img>` (also under link or overlay elements), `<canvas>`, inline
`<svg>`, the current frame of a `<video>`, and CSS `background-image`.
A plain Shift is the only modifier claimed; everything else is left alone.

## Install (once)

Not stow-managed. Load it as an unpacked extension, like VimFields:

1. Open `vivaldi://extensions`, enable **Developer mode**.
2. **Load unpacked** and pick `~/dotfiles/vivaldi/extensions/shift-copy-image`.

Vivaldi remembers unpacked extensions across restarts. After editing the
files, press the reload icon on its card in `vivaldi://extensions`.

## Limits

- Pages served over plain `http://` have no clipboard API, so the copy fails
  there with a toast.
- Cross-origin images are fetched by the background worker. CDNs that reject
  requests without a page `Referer` (hotlink protection) fail with an HTTP
  error toast.
- Animated images are copied as a single frame.
