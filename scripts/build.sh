#!/usr/bin/env bash
# Builds QuickChat and wraps it into build/QuickChat.app (ad-hoc signed).
# Works with just the Xcode Command Line Tools: no Xcode.app needed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/QuickChat.app
SDK_ARGS=()

build() { swift build -c release "${SDK_ARGS[@]+"${SDK_ARGS[@]}"}"; }

mkdir -p build
echo "→ Compiling…"
if ! build >build/.build-log 2>&1; then
  # Some Command-Line-Tools-only setups ship a SwiftUI SDK whose macro plugin is missing
  # ("plugin for module 'SwiftUIMacros' not found"). An older installed SDK works fine.
  DEFAULT_SDK=$(readlink -f "$(xcrun --show-sdk-path)")
  FALLBACK=""
  for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
    [ "$(readlink -f "$sdk")" = "$DEFAULT_SDK" ] || { FALLBACK="$sdk"; break; }
  done
  if [ -n "$FALLBACK" ]; then
    echo "  default SDK failed, retrying with $(basename "$FALLBACK")"
    SDK_ARGS=(--sdk "$FALLBACK")
    build >build/.build-log 2>&1 || { tail -30 build/.build-log; exit 1; }
  else
    tail -30 build/.build-log; exit 1
  fi
fi

BIN="$(swift build -c release "${SDK_ARGS[@]+"${SDK_ARGS[@]}"}" --show-bin-path)/QuickChat"
[ -x "$BIN" ] || { echo "Built binary not found at $BIN"; exit 1; }

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuickChat"
[ -f Resources/AppIcon.icns ] || ./scripts/make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION=$(cat VERSION 2>/dev/null || echo "1.0.0")
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuickChat</string>
  <key>CFBundleDisplayName</key><string>QuickChat</string>
  <key>CFBundleIdentifier</key><string>io.github.mariocodarin.quickchat</string>
  <key>CFBundleExecutable</key><string>QuickChat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <!-- Endpoints are user-supplied; allow plain-http ones too (e.g. a local Ollama on http://localhost). -->
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "→ Ad-hoc signed" || echo "→ (codesign skipped)"
echo "✓ Built $APP"
echo "  Run:      open $APP"
echo "  Install:  cp -R $APP /Applications/"
