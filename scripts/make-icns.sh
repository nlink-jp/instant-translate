#!/usr/bin/env bash
# Generate a macOS .icns from a 1024x1024 source PNG. macOS-only (sips + iconutil).
set -euo pipefail

SRC="${1:?usage: make-icns.sh <source-1024.png> <output.icns>}"
OUT="${2:?usage: make-icns.sh <source-1024.png> <output.icns>}"

if [ ! -f "$SRC" ]; then
  echo "[make-icns] source not found: $SRC" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"

# macOS iconset requires 16/32/128/256/512 at @1x and @2x.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size"             "$SRC" --out "$iconset/icon_${size}x${size}.png"    >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$SRC" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$iconset" -o "$OUT"
echo "[make-icns] wrote $OUT"
