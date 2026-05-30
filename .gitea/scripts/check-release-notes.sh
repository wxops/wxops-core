#!/usr/bin/env bash
# .gitea/scripts/check-release-notes.sh
#
# Convenience helper: generates release-notes/<version>.md from the template
# in release-notes/template.md, with a git-cliff reference block appended.
#
# The file is OPTIONAL. If absent, CI auto-generates the release body from
# git-cliff alone. Only create one when a release warrants human context —
# highlights, breaking-change notes, upgrade instructions, etc.
#
# Usage: bash .gitea/scripts/check-release-notes.sh <version>
#        make release-notes VERSION=vX.Y.Z

set -euo pipefail

NOTES_DIR="release-notes"
TEMPLATE_SRC="${NOTES_DIR}/template.md"

version="${1:?usage: check-release-notes.sh <version>}"
notes_file="${NOTES_DIR}/${version}.md"

if [[ -f "$notes_file" ]]; then
  echo "✓ ${notes_file} already exists — nothing to do"
  exit 0
fi

echo "→ generating ${notes_file} from template"

{
  cat "${TEMPLATE_SRC}"
  printf '\n---\n\n'
  printf '<!-- Reference block: upcoming commits for this release.\n'
  printf '     Use this to write your Highlights, then REMOVE this section.\n'
  printf '     CI appends the final git-cliff changelog automatically. -->\n\n'
  if command -v git-cliff &>/dev/null; then
    git-cliff --unreleased --strip all 2>/dev/null \
      || printf '<!-- git-cliff: no unreleased commits found -->\n'
  else
    printf '<!-- git-cliff not installed — run: pip install git-cliff -->\n'
  fi
} > "${notes_file}"

printf '\n'
printf '   Generated: %s\n' "${notes_file}"
printf '\n'
printf '   Edit it (fill in Highlights / Upgrade notes / Known issues),\n'
printf '   remove the reference block at the bottom, then commit.\n'
printf '\n'
