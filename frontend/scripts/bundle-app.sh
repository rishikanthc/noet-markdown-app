#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bundle-app.sh must run on macOS" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP="$ROOT/.build/MarkdownLab.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$BIN_DIR/MarkdownLab" "$MACOS/MarkdownLab"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none "$APP"
fi

printf '%s\n' "Created $APP"
