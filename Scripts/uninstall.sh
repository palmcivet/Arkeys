#!/usr/bin/env bash
# Quit Arkeys and remove the app plus the files this project persists.

set -euo pipefail

BUNDLE_ID="palmcivet.arkeys"
APP_NAME="Arkeys"

DRY_RUN=0
ASSUME_YES=0
KEEP_APP=0

usage() {
  cat <<EOF
usage: $0 [--dry-run] [--yes] [--keep-app]

  --dry-run   print what would be removed, do not change the system
  --yes       skip the confirmation prompt
  --keep-app  leave Arkeys.app; only delete settings and keymaps
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --keep-app) KEEP_APP=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

HOME_DIR="${HOME:?}"
SUPPORT_DIR="$HOME_DIR/Library/Application Support/Arkeys"
PREFS_PLIST="$HOME_DIR/Library/Preferences/${BUNDLE_ID}.plist"
removed=0

is_safe_target() {
  case "$1" in
    /Applications/Arkeys.app|"$HOME_DIR"/Applications/Arkeys.app|"$SUPPORT_DIR"|"$PREFS_PLIST")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

remove_path() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  if ! is_safe_target "$path"; then
    echo "skip (unsafe path): $path" >&2
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would remove $path"
  elif [[ -d "$path" && ! -L "$path" ]]; then
    rm -rf "$path"
    echo "removed $path"
  else
    rm -f "$path"
    echo "removed $path"
  fi
  removed=$((removed + 1))
}

app_is_running() {
  pgrep -xq "$APP_NAME" 2>/dev/null || pgrep -qf "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null
}

quit_app() {
  if ! app_is_running; then
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would quit ${APP_NAME}"
    return 0
  fi
  echo "quitting ${APP_NAME}…"
  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if ! app_is_running; then
      return 0
    fi
    sleep 0.25
  done
  killall "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.3
  killall -9 "$APP_NAME" >/dev/null 2>&1 || true
}

echo "Arkeys uninstall"
echo
echo "written by this project:"
echo "  $SUPPORT_DIR"
echo "    settings.json"
echo "    Keymaps/{bundleID}/manifest.json"
echo "    Keymaps/{bundleID}/{schemeID}.json"
echo "  $PREFS_PLIST"
echo "    UserDefaults (AppKit creates this when AppleLanguages is cleared)"
echo

if [[ "$KEEP_APP" -eq 0 ]]; then
  echo "also remove:"
  echo "  /Applications/${APP_NAME}.app"
  echo "  $HOME_DIR/Applications/${APP_NAME}.app"
  echo
fi

echo "not removed: PlayCover files you exported yourself."
echo "Accessibility entries live in TCC; remove Arkeys in System Settings if tccutil fails."

if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
  echo
  printf "continue? [y/N] "
  read -r reply || true
  case "$reply" in
    y|Y|yes|YES) ;;
    *)
      echo "aborted"
      exit 1
      ;;
  esac
fi

echo
quit_app

if [[ "$KEEP_APP" -eq 0 ]]; then
  remove_path "/Applications/${APP_NAME}.app"
  remove_path "$HOME_DIR/Applications/${APP_NAME}.app"
fi

remove_path "$SUPPORT_DIR"

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would delete defaults $BUNDLE_ID"
    removed=$((removed + 1))
  else
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    echo "deleted defaults $BUNDLE_ID"
    removed=$((removed + 1))
  fi
fi
remove_path "$PREFS_PLIST"

if command -v tccutil >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would reset TCC for $BUNDLE_ID"
  elif tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "reset TCC entries for $BUNDLE_ID"
  else
    echo "could not reset TCC automatically. Remove Arkeys from"
    echo "  System Settings → Privacy & Security → Accessibility"
    echo "  Input Monitoring  (only if it was listed)"
  fi
fi

echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry run finished ($removed path(s) listed)."
else
  echo "uninstall finished ($removed removed)."
fi
