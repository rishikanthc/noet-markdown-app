#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/MarkdownLab.app"

"$ROOT/scripts/bundle-app.sh"
open -n "$APP" --args "$@"
