#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != '--expected-commit' || "$#" -ne 2 ]]; then
  echo 'Usage: ./scripts/validate.sh --expected-commit <40-char-sha>' >&2
  exit 2
fi
expected="$2"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid commit SHA' >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
root="$(pwd -P)"
git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a Git checkout" >&2; exit 1; }
[[ "$root" == "$git_root" ]] || { echo "Validator must be in the plugin repository root" >&2; exit 1; }
check_source() {
  local head state
  head="$(git rev-parse --verify HEAD 2>/dev/null)" || { echo "Cannot read HEAD" >&2; exit 1; }
  [[ "$head" == "$expected" ]] || { echo "Wrong HEAD: $head (expected $expected)" >&2; exit 1; }
  state="$(git status --porcelain=v1 --untracked-files=all)" || { echo "Cannot check working tree" >&2; exit 1; }
  [[ -z "$state" ]] || { echo "Working tree must be clean" >&2; exit 1; }
}
check_source
printf "Validating plugin commit %s\n" "$expected"
for f in hooks/pre-checkout hooks/pre-exit tests/plugin.sh; do bash -n "$f"; done
if command -v git >/dev/null 2>&1; then git diff --check; fi
bash tests/plugin.sh
check_source
echo "Plugin validation PASSED for $expected (clean)"
