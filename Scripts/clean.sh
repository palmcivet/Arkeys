#!/usr/bin/env bash
# Remove locally generated caches and package output from this checkout,
# including this project's Xcode DerivedData.

set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
KEEP_DIST=0

usage() {
  cat <<EOF
usage: $0 [--dry-run] [--yes] [--keep-dist]

  --dry-run    print what would be removed, do not delete
  --yes        skip the confirmation prompt
  --keep-dist  leave dist/; only delete caches and DerivedData
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --keep-dist) KEEP_DIST=1 ;;
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

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:?}"
DERIVED_DATA="$HOME_DIR/Library/Developer/Xcode/DerivedData"
removed=0

if [[ ! -d "$ROOT/Arkeys.xcodeproj" ]]; then
  echo "run from an Arkeys checkout (missing Arkeys.xcodeproj)" >&2
  exit 1
fi

belongs_to_checkout() {
  local workspace="$1"
  case "$workspace" in
    "$ROOT"|"$ROOT"/Arkeys.xcodeproj) return 0 ;;
    *) return 1 ;;
  esac
}

is_safe_target() {
  local path="$1"
  case "$path" in
    "$ROOT"/dist|"$ROOT"/Packages/*/.build)
      return 0
      ;;
    "$HOME_DIR"/Library/Developer/Xcode/DerivedData/Arkeys-*)
      [[ "$(dirname "$path")" == "$DERIVED_DATA" ]] || return 1
      [[ "$(basename "$path")" == Arkeys-* ]] || return 1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_derived_data() {
  local dir workspace

  [[ -d "$DERIVED_DATA" ]] || return 0

  shopt -s nullglob
  for dir in "$DERIVED_DATA"/Arkeys-*; do
    [[ -d "$dir" || -L "$dir" ]] || continue
    [[ "$(dirname "$dir")" == "$DERIVED_DATA" ]] || continue
    [[ "$(basename "$dir")" == Arkeys-* ]] || continue
    [[ -f "$dir/info.plist" ]] || continue
    workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dir/info.plist" 2>/dev/null || true)"
    belongs_to_checkout "$workspace" || continue
    printf '%s\n' "$dir"
  done
  shopt -u nullglob
}

collect_targets() {
  local pkg

  if [[ "$KEEP_DIST" -eq 0 ]]; then
    printf '%s\n' "$ROOT/dist"
  fi

  shopt -s nullglob
  for pkg in "$ROOT/Packages"/*; do
    [[ -d "$pkg" ]] || continue
    printf '%s\n' "$pkg/.build"
  done
  shopt -u nullglob

  collect_derived_data
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

existing=()
while IFS= read -r path; do
  if [[ -e "$path" || -L "$path" ]]; then
    existing+=("$path")
  fi
done < <(collect_targets | awk '!seen[$0]++')

echo "Arkeys clean"
echo

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "nothing to clean."
  exit 0
fi

echo "locally generated:"
for path in "${existing[@]}"; do
  echo "  $path"
done

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
for path in "${existing[@]}"; do
  remove_path "$path"
done

echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry run finished ($removed path(s) listed)."
else
  echo "clean finished ($removed removed)."
fi
