#!/usr/bin/env bash
# Builds the app icon from Resources/AppIcon.icon (an Icon Composer document).
#   scripts/make-icon.sh
# Writes, all committed so the app still builds with only the Command Line Tools:
#   Resources/Assets.car    macOS 26+: Liquid Glass, follows light/dark/tinted/clear
#   Resources/AppIcon.icns  macOS 13–25: the light rendering
#   docs/logo/winlego-512.png
# Needs Xcode (actool and Icon Composer's ictool); XCODE overrides its location.
set -euo pipefail
cd "$(dirname "$0")/.."

XCODE="${XCODE:-/Applications/Xcode.app}"
export DEVELOPER_DIR="$XCODE/Contents/Developer"
ictool="$XCODE/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
src=Resources/AppIcon.icon

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

xcrun actool "$src" --compile "$work" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist "$work/partial.plist" >/dev/null
cp "$work/Assets.car" Resources/Assets.car

render() {  # size, output
  "$ictool" "$src" --export-image --output-file "$2" --platform macOS --rendition Default \
    --width "$1" --height "$1" --scale 1 >/dev/null
}
mkdir -p "$work/AppIcon.iconset"
for base in 16 32 128 256 512; do
  render "$base" "$work/AppIcon.iconset/icon_${base}x${base}.png"
  render $((base * 2)) "$work/AppIcon.iconset/icon_${base}x${base}@2x.png"
done
iconutil -c icns "$work/AppIcon.iconset" -o Resources/AppIcon.icns
render 512 docs/logo/winlego-512.png

echo "wrote Resources/Assets.car, Resources/AppIcon.icns, docs/logo/winlego-512.png"
