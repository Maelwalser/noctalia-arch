#!/usr/bin/env bash
#
# Install the VimFields Vivaldi UI mod.
#
# Copies custom.js into Vivaldi's resources directory and injects a <script>
# tag into window.html, so Vim keybindings work in Vivaldi's OWN chrome input
# fields (address bar, search, panels) — which a normal extension content
# script cannot reach.
#
# Idempotent and safe to re-run. Vivaldi rewrites window.html on every update,
# which removes the injection, so RE-RUN THIS after each Vivaldi upgrade.
#
# Usage:
#   sudo ./install.sh              # install / re-install
#   sudo ./install.sh --uninstall  # remove the mod
#   sudo ./install.sh --dir=/path/to/resources/vivaldi
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUNDLE="$SCRIPT_DIR/custom.js"
readonly MARKER_START="<!-- vimfields:start -->"
readonly MARKER_END="<!-- vimfields:end -->"

uninstall=0
dir_override=""
for arg in "$@"; do
  case "$arg" in
    --uninstall) uninstall=1 ;;
    --dir=*)     dir_override="${arg#--dir=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Writing into Vivaldi's install dir needs root." >&2
  echo "Re-run: sudo $0 $*" >&2
  exit 1
fi

find_resources() {
  if [[ -n "$dir_override" ]]; then
    [[ -d "$dir_override" ]] || { echo "--dir not found: $dir_override" >&2; exit 1; }
    printf '%s\n' "$dir_override"; return
  fi
  local c
  for c in \
    /opt/vivaldi/resources/vivaldi \
    /opt/vivaldi-snapshot/resources/vivaldi \
    /usr/share/vivaldi/resources/vivaldi \
    /usr/lib/vivaldi/resources/vivaldi
  do
    [[ -d "$c" ]] && { printf '%s\n' "$c"; return; }
  done
  echo "Could not find Vivaldi resources dir. Pass --dir=<path>." >&2
  exit 1
}

readonly RES="$(find_resources)"
echo "Vivaldi resources: $RES"

# Modern Vivaldi uses window.html; older builds used browser.html.
html=""
for name in window.html browser.html; do
  [[ -f "$RES/$name" ]] && { html="$RES/$name"; break; }
done
[[ -n "$html" ]] || { echo "No window.html/browser.html in $RES" >&2; exit 1; }

# Print $html with any existing vimfields block removed (idempotent).
strip_block() {
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    index($0, s) { skip = 1 }
    !skip        { print }
    index($0, e) { skip = 0 }
  ' "$html"
}

# cat > "$html" (rather than mv) preserves the file owner/permissions, which
# matters because it lives in a root-owned system directory.
if [[ $uninstall -eq 1 ]]; then
  strip_block > "$html.tmp" && cat "$html.tmp" > "$html" && rm -f "$html.tmp"
  rm -rf "$RES/vimfields"
  echo "Unpatched $html"
  echo "Removed   $RES/vimfields"
  echo "Done. Restart Vivaldi."
  exit 0
fi

[[ -f "$BUNDLE" ]] || { echo "Bundle missing: $BUNDLE" >&2; exit 1; }

install -Dm644 "$BUNDLE" "$RES/vimfields/custom.js"
echo "Copied  $RES/vimfields/custom.js"

# Re-insert the script tag immediately before </body>.
strip_block | awk -v s="$MARKER_START" -v e="$MARKER_END" '
  /<\/body>/ && !done {
    print s
    print "<script src=\"vimfields/custom.js\"></script>"
    print e
    done = 1
  }
  { print }
' > "$html.tmp" && cat "$html.tmp" > "$html" && rm -f "$html.tmp"
echo "Patched $html"
echo "Done. Fully quit and restart Vivaldi to load the mod."
