#!/usr/bin/env bash
# Capture / shrink simulator screenshots at a size that is cheap to keep in an
# agent's context. Full-resolution PNGs enter the conversation as base64 and are
# re-uploaded on every subsequent turn, so they are worth shrinking once here.
#
#   ./scripts/shot.sh player            # capture booted simulator -> /tmp/sonar-shots/player.jpg
#   ./scripts/shot.sh --shrink /tmp/shots   # convert existing images in place-adjacent dir
#
# Env overrides: SHOT_DIR, SHOT_WIDTH, SHOT_QUALITY
set -euo pipefail

SHOT_DIR="${SHOT_DIR:-/tmp/sonar-shots}"
SHOT_WIDTH="${SHOT_WIDTH:-640}"
SHOT_QUALITY="${SHOT_QUALITY:-60}"

shrink() {
  local src="$1" dst="$2"
  sips --resampleWidth "$SHOT_WIDTH" \
       -s format jpeg -s formatOptions "$SHOT_QUALITY" \
       "$src" --out "$dst" >/dev/null
  printf '%s  (%s KB)\n' "$dst" "$(( $(stat -f%z "$dst") / 1024 ))"
}

if [[ "${1:-}" == "--shrink" ]]; then
  target="${2:?usage: shot.sh --shrink <file|dir>}"
  out="$SHOT_DIR"
  mkdir -p "$out"
  if [[ -d "$target" ]]; then
    shopt -s nullglob
    for f in "$target"/*.{png,jpg,jpeg,PNG,JPG}; do
      shrink "$f" "$out/$(basename "${f%.*}").jpg"
    done
  else
    shrink "$target" "$out/$(basename "${target%.*}").jpg"
  fi
  exit 0
fi

name="${1:-shot}"
mkdir -p "$SHOT_DIR"

if ! xcrun simctl list devices booted 2>/dev/null | grep -q '(Booted)'; then
  echo "no booted simulator; start one first (open -a Simulator)" >&2
  exit 1
fi

raw="$(mktemp -t sonarshot).png"
trap 'rm -f "$raw"' EXIT
xcrun simctl io booted screenshot "$raw" >/dev/null 2>&1
shrink "$raw" "$SHOT_DIR/$name.jpg"
