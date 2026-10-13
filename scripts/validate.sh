#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for f in hooks/pre-checkout hooks/pre-exit tests/plugin.sh; do bash -n "$f"; done
if command -v git >/dev/null 2>&1; then git diff --check; fi
bash tests/plugin.sh
echo 'Plugin validation PASSED'
