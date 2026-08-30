#!/usr/bin/env bash
# Build a Release Arkeys.app and zip.
# Usage: scripts/package.sh <version> [output-dir]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <version> [output-dir]" >&2
  exit 1
fi

VERSION="$1"
if [[ -z "$VERSION" ]]; then
  echo "version must not be empty" >&2
  exit 1
fi

# xcodebuild needs a full Xcode, not Command Line Tools.
# Prefer an explicit DEVELOPER_DIR, then Xcode.app, so local runs work
# even when `xcode-select -p` is /Library/Developer/CommandLineTools.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  fi
fi

if ! command -v xcodebuild >/dev/null || ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild requires Xcode.app. Install Xcode or run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${2:-"$ROOT/dist"}"
ARCHIVE_PATH="$OUT/Arkeys.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Arkeys.app"
ZIP_NAME="Arkeys-${VERSION}.zip"

cd "$ROOT"
mkdir -p "$OUT"

xcodebuild \
  -project Arkeys.xcodeproj \
  -scheme Arkeys \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/.derivedData" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "expected archive product at $APP_PATH" >&2
  exit 1
fi

ditto -c -k --keepParent "$APP_PATH" "$OUT/$ZIP_NAME"

(
  cd "$OUT"
  shasum -a 256 "$ZIP_NAME" > SHA256SUMS
)

echo "packaged $OUT/$ZIP_NAME"
