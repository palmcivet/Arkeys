#!/usr/bin/env bash
# Build Arkeys.app and run Swift package tests.
# App-level XCTest targets have no sources; package tests are the suite.

set -euo pipefail

# xcodebuild / swift need a full Xcode, not Command Line Tools.
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

if [[ ! -d "$ROOT/Arkeys.xcodeproj" ]]; then
  echo "run from an Arkeys checkout (missing Arkeys.xcodeproj)" >&2
  exit 1
fi

cd "$ROOT"

echo "==> xcodebuild build -scheme Arkeys"
xcodebuild \
  -project Arkeys.xcodeproj \
  -scheme Arkeys \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

tested=0
shopt -s nullglob
for pkg in "$ROOT/Packages"/*; do
  [[ -f "$pkg/Package.swift" ]] || continue
  grep -qE '[[:space:]]*\.testTarget\(' "$pkg/Package.swift" || continue
  echo "==> swift test --package-path ${pkg#"$ROOT"/}"
  swift test --package-path "$pkg"
  tested=$((tested + 1))
done
shopt -u nullglob

if [[ "$tested" -eq 0 ]]; then
  echo "no Swift package test targets found" >&2
  exit 1
fi

echo "ok: built Arkeys and ran tests in $tested package(s)"
