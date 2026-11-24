#!/usr/bin/env bash
# Renders Resources/icon.svg into Resources/AppIcon.icns and docs/logo.png.
# Needs: rsvg-convert (brew install librsvg) and iconutil (ships with macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

SVG=Resources/icon.svg
SET=build/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET" docs

render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$SET/$2"; }
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o Resources/AppIcon.icns
rsvg-convert -w 512 -h 512 "$SVG" -o docs/logo.png
echo "✓ Resources/AppIcon.icns and docs/logo.png"
