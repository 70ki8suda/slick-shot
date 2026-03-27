#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPDATES_DIR="${1:-$ROOT_DIR/dist/updates}"
APPCAST_FILENAME="${APPCAST_FILENAME:-appcast.xml}"

mkdir -p "$UPDATES_DIR"

GENERATE_APPCAST_TOOL="$(
  find "$ROOT_DIR" \
    -path '*Sparkle*/bin/generate_appcast' \
    -type f \
    | head -n 1
)"

if [[ -z "$GENERATE_APPCAST_TOOL" ]]; then
  echo "Unable to locate generate_appcast. Build the package once so Sparkle artifacts are downloaded." >&2
  exit 1
fi

"$GENERATE_APPCAST_TOOL" "$UPDATES_DIR"

if [[ ! -f "$UPDATES_DIR/$APPCAST_FILENAME" ]]; then
  echo "Expected $UPDATES_DIR/$APPCAST_FILENAME to be generated" >&2
  exit 1
fi

echo "Generated $UPDATES_DIR/$APPCAST_FILENAME"
