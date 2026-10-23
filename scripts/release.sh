#!/usr/bin/env bash
# Builds the release zip for a version and prints what the cask needs.
#   scripts/release.sh 0.1.0
# Then: git tag v0.1.0 && git push --tags, upload dist/winlego-0.1.0.zip to the GitHub release
# (gh release create v0.1.0 dist/winlego-0.1.0.zip), and update packaging/homebrew/winlego.rb.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"

scripts/test.sh
VERSION="$VERSION" scripts/bundle.sh

mkdir -p dist
zip="dist/winlego-$VERSION.zip"
rm -f "$zip"
ditto -c -k --keepParent build/winlego.app "$zip"

echo
echo "zip:     $zip"
echo "version: $VERSION"
echo "sha256:  $(shasum -a 256 "$zip" | cut -d' ' -f1)"
