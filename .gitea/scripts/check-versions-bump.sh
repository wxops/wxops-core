#!/usr/bin/env bash
# .gitea/scripts/check-versions-bump.sh
#
# Pre-commit hook: ensures VERSIONS.yaml carries a version bump for every
# package whose YAML files are staged for commit.
#
# Reads VERSIONS.yaml from the index (staged state) so the developer can
# include the bump in the same commit as the package change.
#
# Triggers on: any .yaml change under package/<name>/ for known packages.
# Skips:       non-YAML files (README.md etc.) and first-ever release (no tag).

set -euo pipefail

PACKAGES=(gitea-user gitea-org gitea-team gitea-repository)
VERSIONS_FILE="VERSIONS.yaml"
FAILED=()

staged=$(git diff --cached --name-only 2>/dev/null)
[ -z "$staged" ] && exit 0

last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

# Read VERSIONS.yaml from the index so a staged bump is visible immediately.
# Fall back to the working-tree file if VERSIONS.yaml itself is not staged.
staged_yaml=$(git show ":${VERSIONS_FILE}" 2>/dev/null || cat "${VERSIONS_FILE}" 2>/dev/null || echo "")

for pkg in "${PACKAGES[@]}"; do
  # Only check packages that have staged YAML changes
  if ! echo "$staged" | grep -qE "^package/${pkg}/.*\.yaml$"; then
    continue
  fi

  curr_ver=$(printf '%s' "$staged_yaml" | python3 -c "
import yaml, sys
d = yaml.safe_load(sys.stdin)
print(d.get('packages', {}).get('${pkg}', {}).get('package', {}).get('current', ''))
" 2>/dev/null || echo "")

  # No previous tag means first release — any version is fine
  if [ -z "$last_tag" ]; then
    continue
  fi

  prev_ver=$(git show "${last_tag}:${VERSIONS_FILE}" 2>/dev/null | python3 -c "
import yaml, sys
d = yaml.safe_load(sys.stdin)
print(d.get('packages', {}).get('${pkg}', {}).get('package', {}).get('current', ''))
" 2>/dev/null || echo "")

  if [ "$curr_ver" = "$prev_ver" ]; then
    FAILED+=("${pkg}  (still ${curr_ver} — same as ${last_tag})")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  printf '\n'
  printf '✗  package YAML staged without a version bump in %s:\n' "${VERSIONS_FILE}"
  for item in "${FAILED[@]}"; do
    printf '     • %s\n' "$item"
  done
  printf '\n'
  printf '   Bump the version in %s, stage the file, then commit.\n' "${VERSIONS_FILE}"
  printf '   See VERSIONS.yaml comments for patch / minor / major rules.\n'
  printf '\n'
  exit 1
fi

exit 0
