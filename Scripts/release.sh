#!/usr/bin/env bash
# The script prepares release notes and version, then creates a commit.

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

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "release must be run inside a Git repository" >&2
  exit 1
fi

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "version file not found: $VERSION_FILE" >&2
  exit 1
fi

if ! git diff --quiet ||
   ! git diff --cached --quiet ||
   [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "working tree must be clean before preparing a release" >&2
  git status --short >&2
  exit 1
fi

version_values="$(
  awk '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    {
      separator = index($0, "=")
      if (!separator) {
        next
      }

      key = trim(substr($0, 1, separator - 1))
      value = trim(substr($0, separator + 1))
      sub(/[[:space:]]*\/\/.*/, "", value)
      value = trim(value)

      if (key == "MARKETING_VERSION") {
        marketing_version = value
        marketing_found++
      } else if (key == "CURRENT_PROJECT_VERSION") {
        current_project_version = value
        build_found++
      }
    }

    END {
      if (marketing_found != 1 || build_found != 1) {
        exit 1
      }
      printf "%s\t%s\n", marketing_version, current_project_version
    }
  ' "$VERSION_FILE"
)" || {
  echo "MARKETING_VERSION and CURRENT_PROJECT_VERSION are required exactly once in $VERSION_FILE" >&2
  exit 1
}

IFS=$'\t' read -r current_version current_build <<< "$version_values"
if [[ -z "$current_version" || -z "$current_build" ]]; then
  echo "MARKETING_VERSION and CURRENT_PROJECT_VERSION are required in $VERSION_FILE" >&2
  exit 1
fi

if [[ ! "$current_build" =~ ^[0-9]+$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be an integer: $current_build" >&2
  exit 1
fi

release_commit="$(
  git log -1 --first-parent --no-merges \
    --format='%H' --grep='^chore(release): v' HEAD
)"
release_ref=""
release_label="the beginning of the repository"

if [[ -n "$release_commit" ]]; then
  release_ref="$release_commit"
  release_label="$(git show -s --format='%s' "$release_commit")"
else
  release_tag="$(git describe --tags --match='v[0-9]*' --abbrev=0 HEAD 2>/dev/null || true)"
  if [[ -n "$release_tag" ]]; then
    release_ref="$release_tag"
    release_label="$release_tag"
  fi
fi

log_range=HEAD
if [[ -n "$release_ref" ]]; then
  log_range="$release_ref..HEAD"
fi

generated_notes="$(
  git log "$log_range" --no-merges --reverse --format='- %s (%h)'
)"

if [[ -z "$generated_notes" ]]; then
  echo "no commits found since $release_label; nothing to release" >&2
  exit 1
fi

printf '%s\n' "$generated_notes" > "$RELEASE_NOTE_FILE"
echo "Release notes from $release_label to HEAD were written to:"
echo "  .release-note"

read -r -p "Confirm these release notes and continue? [y/N] " notes_confirm
if [[ ! "$notes_confirm" =~ ^[Yy]$ ]]; then
  echo "release cancelled"
  exit 0
fi

if [[ ! -s "$RELEASE_NOTE_FILE" ]] ||
   [[ -z "$(sed '/^[[:space:]]*$/d' "$RELEASE_NOTE_FILE")" ]]; then
  echo "release notes are empty; release cancelled" >&2
  exit 1
fi

while :; do
  read -r -p "New marketing version (current: $current_version): " new_version
  if [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] &&
     [[ "$new_version" != "$current_version" ]]; then
    break
  fi
  echo "enter a different semantic version such as 0.2.0 or 1.0.0-rc.1" >&2
done

next_build=$((current_build + 1))
echo
echo "The release will:"
echo "  version: $current_version -> $new_version"
echo "  build:   $current_build -> $next_build"
echo "  commit:  chore(release): v$new_version"

version_tmp="$(mktemp "${TMPDIR:-/tmp}/arkeys-version.XXXXXX")"
commit_message_tmp="$(mktemp "${TMPDIR:-/tmp}/arkeys-commit-message.XXXXXX")"
cleanup_files() {
  rm -f "$version_tmp" "$commit_message_tmp"
}
trap cleanup_files EXIT

awk -v version="$new_version" -v build="$next_build" '
  function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    return value
  }

  {
    separator = index($0, "=")
    if (!separator) {
      print
      next
    }

    key = trim(substr($0, 1, separator - 1))
    if (key == "MARKETING_VERSION") {
      value = version
      marketing_found++
    } else if (key == "CURRENT_PROJECT_VERSION") {
      value = build
      build_found++
    } else {
      print
      next
    }

    prefix = substr($0, 1, separator)
    suffix = substr($0, separator + 1)
    comment = ""
    if (match(suffix, /[[:space:]]*\/\/.*/)) {
      comment = substr(suffix, RSTART)
    }
    print prefix " " value comment
  }

  END {
    if (marketing_found != 1 || build_found != 1) {
      exit 1
    }
  }
' "$VERSION_FILE" > "$version_tmp"
mv "$version_tmp" "$VERSION_FILE"

{
  printf 'chore(release): v%s\n\n' "$new_version"
  cat "$RELEASE_NOTE_FILE"
  printf '\n'
} > "$commit_message_tmp"

git add "$VERSION_FILE"
git commit -F "$commit_message_tmp"
rm -f "$RELEASE_NOTE_FILE"

echo "created release commit for v$new_version"
echo "push it or merge its PR into master to publish the release"
