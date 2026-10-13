#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != '--expected-commit' || "$#" -ne 2 ]]; then
  echo 'Usage: ./scripts/validate.sh --expected-commit <40-char-sha>' >&2
  exit 2
fi
expected="$2"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid commit SHA' >&2; exit 2; }
head="$(git rev-parse --verify HEAD)"
[[ "$head" == "$expected" ]] || { echo "Wrong HEAD: $head (expected $expected)" >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || { echo 'Working tree must be clean' >&2; exit 1; }
for f in hooks/pre-checkout hooks/pre-exit tests/plugin.sh; do bash -n "$f"; done
if command -v git >/dev/null 2>&1; then git diff --check; fi
bash tests/plugin.sh
[[ "$(git rev-parse --verify HEAD)" == "$expected" ]] || { echo 'HEAD changed during validation' >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || { echo 'Working tree changed during validation' >&2; exit 1; }
echo "Plugin validation PASSED for $expected"
