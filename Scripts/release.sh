#!/usr/bin/env bash
# Validate and create a release commit.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/Config/Version.xcconfig"
RELEASE_NOTE_FILE="$ROOT/.release-note"

usage() {
  cat <<EOF
Usage: $0

Prepare a release from the commits since the previous release.

The generated release notes are written to:
  .release-note
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

cd "$ROOT"

if ! git diff --quiet ||
   ! git diff --cached --quiet ||
   [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "working tree must be clean before preparing a release" >&2
  git status --short >&2
  exit 1
fi

version_tmp=""
commit_message_tmp=""
cleanup() {
  rm -f "$RELEASE_NOTE_FILE"
  [[ -z "$version_tmp" ]] || rm -f "$version_tmp"
  [[ -z "$commit_message_tmp" ]] || rm -f "$commit_message_tmp"
}
trap cleanup EXIT

current_version="$(
  awk '$1 == "MARKETING_VERSION" { print $3; exit }' "$VERSION_FILE"
)"
current_build="$(
  awk '$1 == "CURRENT_PROJECT_VERSION" { print $3; exit }' "$VERSION_FILE"
)"
if [[ -z "$current_version" || -z "$current_build" ]]; then
  echo "MARKETING_VERSION and CURRENT_PROJECT_VERSION are required in $VERSION_FILE" >&2
  exit 1
fi

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be an integer: $current_build" >&2
  exit 1
fi

previous_tag="$(
  git describe --tags --match='v[0-9]*' --abbrev=0 HEAD 2>/dev/null || true
)"
range="HEAD"
if [[ -n "$previous_tag" ]]; then
  range="$previous_tag..HEAD"
fi

git log "$range" --no-merges --reverse --format='- %s (%h)' > "$RELEASE_NOTE_FILE"
if [[ ! -s "$RELEASE_NOTE_FILE" ]]; then
  echo "no commits found since ${previous_tag:-the repository began}" >&2
  rm -f "$RELEASE_NOTE_FILE"
  exit 1
fi

echo "Release notes for $range were written to:"
echo "  .release-note"

read -r -p "Continue with these release notes? [y/N] " notes_confirm
if [[ ! "$notes_confirm" =~ ^[Yy]$ ]]; then
  echo "release cancelled"
  exit 0
fi
if [[ ! -s "$RELEASE_NOTE_FILE" ]]; then
  echo ".release-note must not be empty" >&2
  exit 1
fi

while :; do
  read -r -p "New marketing version (current: $current_version): " new_version
  if [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] &&
     [[ "$new_version" != "$current_version" ]]; then
    break
  fi
  echo "enter a different semantic version such as 0.2.0 or 1.0.0-rc.1" >&2
done

next_build=$((current_build + 1))
tag="v$new_version"

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
  echo "tag already exists: $tag" >&2
  exit 1
fi

echo
echo "The release will:"
echo "  version: $current_version -> $new_version"
echo "  build:   $current_build -> $next_build"
echo "  commit:  chore(release): v$new_version"

read -r -p "Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "release cancelled"
  exit 0
fi

version_tmp="$(mktemp "${TMPDIR:-/tmp}/arkeys-version.XXXXXX")"
commit_message_tmp="$(mktemp "${TMPDIR:-/tmp}/arkeys-commit-message.XXXXXX")"

awk -v version="$new_version" -v build="$next_build" '
  /^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {
    print "MARKETING_VERSION = " version
    next
  }
  /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
    print "CURRENT_PROJECT_VERSION = " build
    next
  }
  { print }
' "$VERSION_FILE" > "$version_tmp"
cat "$version_tmp" > "$VERSION_FILE"

{
  printf 'chore(release): %s\n\n' "$tag"
  cat "$RELEASE_NOTE_FILE"
  printf '\n'
} > "$commit_message_tmp"

git add "$VERSION_FILE"
git commit -F "$commit_message_tmp"

echo "created release commit for $tag"
echo "push it or merge its PR into master to publish the release"
