#!/bin/zsh
# install.command – build VideoEditor.app and install to ~/Applications
# Usage: ./install.command [--open]

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_NAME="VideoEditor"
BUNDLE_ID="com.example.videoeditor"
MIN_MACOS="14.0"
INSTALL_DIR="$HOME/Applications"

# ── Resolve script directory so this works when double-clicked in Finder ──────
SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

# ── Flags ─────────────────────────────────────────────────────────────────────
OPEN_AFTER=0
for arg in "$@"; do
  [[ "$arg" == "--open" ]] && OPEN_AFTER=1
done

# ── Clean ─────────────────────────────────────────────────────────────────────
echo "▶ Cleaning previous build…"
swift package clean 2>&1

# ── Build ─────────────────────────────────────────────────────────────────────
echo "▶ Building $APP_NAME (release)…"
swift build -c release 2>&1

BINARY=".build/release/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
  echo "✘ Build succeeded but binary not found at $BINARY" >&2
  exit 1
fi

# ── Assemble .app bundle ──────────────────────────────────────────────────────
STAGING="$(mktemp -d)/$APP_NAME.app"
CONTENTS="$STAGING/Contents"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

echo "▶ Assembling $APP_NAME.app…"

# Binary
cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>             <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>      <string>Video Editor</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key>          <string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>NSPrincipalClass</key>         <string>NSApplication</string>
  <key>LSMinimumSystemVersion</key>   <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>NSPhotoLibraryUsageDescription</key>
    <string>Required to import videos from your photo library.</string>
</dict>
</plist>
PLIST

# ── Install ───────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
DEST="$INSTALL_DIR/$APP_NAME.app"

# Remove previous installation if present
if [[ -d "$DEST" ]]; then
  echo "▶ Removing existing $DEST…"
  rm -rf "$DEST"
fi

echo "▶ Installing to $DEST…"
cp -R "$STAGING" "$DEST"
rm -rf "$(dirname "$STAGING")"

echo "✔ Installed $APP_NAME.app → $DEST"

# ── Open ──────────────────────────────────────────────────────────────────────
if (( OPEN_AFTER )); then
  echo "▶ Opening $APP_NAME…"
  open "$DEST"
fi
