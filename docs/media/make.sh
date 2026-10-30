#!/usr/bin/env bash
# Regenerates every picture and video in docs/: stills into docs/img, demo videos
# into docs/media. Needs Google Chrome and Node 22+ (no npm packages).
#   docs/media/make.sh            all
#   docs/media/make.sh stills     only the screenshots
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="${TMPDIR:-/tmp}/winlego-media"

node "$here/capture.mjs" stills
[ "${1:-}" = stills ] && exit 0

for lang in en ko; do
  node "$here/capture.mjs" frames "$lang" "$work/$lang" 30
  swift "$here/encode.swift" "$work/$lang" 30 "$here/demo-$lang.mp4" "$here/demo-$lang.gif" 720 12
done
rm -rf "$work"
ls -lh "$here"/demo-* "$here"/../img/*.png
