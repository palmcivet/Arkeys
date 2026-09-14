#!/usr/bin/env bash
# Build a Release Arkeys.app zip.
# Writes the zip and checksum to dist/ (or [output-dir]).

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [version] [output-dir]

Build a Release Arkeys.app zip.

  version     optional marketing version; defaults to Config/Version.xcconfig
  output-dir  optional destination directory; defaults to dist/
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(
    xcodebuild \
      -project "$ROOT/Arkeys.xcodeproj" \
      -scheme Arkeys \
      -configuration Release \
      -destination 'generic/platform=macOS' \
      -showBuildSettings \
      -json 2>/dev/null |
      plutil -extract '0.buildSettings.MARKETING_VERSION' raw -o - -
  )"
fi

OUT="${2:-"$ROOT/dist"}"
ZIP_NAME="Arkeys-${VERSION}.zip"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/arkeys-package.XXXXXX")"
ARCHIVE_PATH="$WORK/Arkeys.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Arkeys.app"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
mkdir -p "$OUT"

xcodebuild \
  -project Arkeys.xcodeproj \
  -scheme Arkeys \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
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
