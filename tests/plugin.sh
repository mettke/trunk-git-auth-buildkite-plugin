#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/empty"
cat > "$tmp/bin/buildkite-agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "oidc request-token --audience ${MOCK_EXPECTED_AUDIENCE:-https://app.trunk.dev/v1/git/buildkite} --claim build_id,pipeline_id" ]] || exit 81
printf 'called\n' >> "$CALLS"
printf 'eyJhbGciOiJSUzI1NiJ9.eyJqb2IiOiJtb2NrIn0.sigmock\n'
AGENT
chmod 700 "$tmp/bin/buildkite-agent"
export PATH="$tmp/bin:$PATH" HOME="$tmp/home" TMPDIR="$tmp"
export CALLS="$tmp/oidc.log"
export TRUNK_BUILDKITE_GIT_REMOTE='https://app.trunk.dev/v1/git/acme/fixture.git'
export TRUNK_BUILDKITE_OIDC_AUDIENCE='https://app.trunk.dev/v1/git/buildkite'
export BUILDKITE_REPO="$TRUNK_BUILDKITE_GIT_REMOTE" BUILDKITE_BRANCH='_trunk/candidates/chg_abc123/r1'
export BUILDKITE_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export MOCK_EXPECTED_AUDIENCE="$TRUNK_BUILDKITE_OIDC_AUDIENCE"

# Protect against ambient personal/global Git helpers hijacking Trunk auth.
# For the exact Trunk URL the plugin must reset such helpers in process-only
# Git configuration; never edit the operator's global .gitconfig.
cat > "$tmp/bin/ambient-helper" <<'AMBIENT'
#!/usr/bin/env bash
printf 'ambient used\n' >> "$AMBIENT_CALLS"
printf 'username=wrong\npassword=wrong\n'
AMBIENT
chmod 700 "$tmp/bin/ambient-helper"
export AMBIENT_CALLS="$tmp/ambient.log"
printf '[credential]\n  helper = %s\n' "$tmp/bin/ambient-helper" > "$HOME/.gitconfig"
# Both modes must work in an empty workspace. Source the hook to emulate
# agent hook environment export; no real Buildkite API or server is mocked here.
cd "$tmp/empty"
for mode in true false; do
  (
    export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT="$mode"
    export BUILDKITE_SKIP_CHECKOUT=false
    source "$root/hooks/pre-checkout"
    [[ "$GIT_CONFIG_COUNT" == 3 && "$GIT_ASKPASS" == false && "$GIT_TERMINAL_PROMPT" == 0 && -x "$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper" ]]
    if [[ "$mode" == false ]]; then [[ "$BUILDKITE_SKIP_CHECKOUT" == true ]]; else [[ "$BUILDKITE_SKIP_CHECKOUT" == false ]]; fi
    [[ ! -e .git ]]
    for i in 1 2; do
      output="$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | git credential fill)"
      [[ "$output" == *'username=trunk-byo'* && "$output" == *'password=eyJhbGciOiJSUzI1NiJ9.eyJqb2IiOiJtb2NrIn0.sigmock'* ]]
    done
    helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
    [[ -z "$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/other.git\n\n' | "$helper" get)" ]]
    [[ -z "$(printf 'protocol=https\nhost=other.example\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]]
    [[ -z "$(printf 'protocol=http\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]]
    source "$root/hooks/pre-exit"
    [[ ! -e "$helper" ]]
  )
done
[[ "$(wc -l < "$CALLS")" == 4 ]]
[[ ! -s "$AMBIENT_CALLS" ]] || { echo 'ambient Git credentials were used' >&2; exit 4; }
[[ "$(cat "$HOME/.gitconfig")" == "$(printf '[credential]\n  helper = %s' "$tmp/bin/ambient-helper")" ]] ||
  { echo 'global Git config was mutated' >&2; exit 5; }

# The exact-host pin must work on an isolated Preview without falling back to
# Production, including Git credential URL matching.
(
  export TRUNK_BUILDKITE_GIT_REMOTE='https://eng302-preview.example.test/v1/git/acme/fixture.git'
  export TRUNK_BUILDKITE_OIDC_AUDIENCE='https://eng302-preview.example.test/v1/git/buildkite'
  export MOCK_EXPECTED_AUDIENCE="$TRUNK_BUILDKITE_OIDC_AUDIENCE"
  export BUILDKITE_REPO="$TRUNK_BUILDKITE_GIT_REMOTE"
  export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
  source "$root/hooks/pre-checkout"
  credential="$(printf 'protocol=https\nhost=eng302-preview.example.test\npath=v1/git/acme/fixture.git\n\n' | git credential fill)"
  [[ "$credential" == *'username=trunk-byo'* ]] || exit 6
  helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
  [[ -z "$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]] || exit 7
  source "$root/hooks/pre-exit"
  [[ ! -e "$helper" ]] || exit 8
)
[[ "$(wc -l < "$CALLS")" == 5 ]] || { echo 'isolated Preview OIDC request missing' >&2; exit 9; }
[[ ! -s "$AMBIENT_CALLS" ]] || { echo 'ambient Git helper used in Preview' >&2; exit 10; }

# Legacy immutable ref shape remains a syntax-only acceptance; actual Git
# authority for the historical ref is independently checked by Trunk Core.
(
  export BUILDKITE_BRANCH='trunk/candidates/chg_abc123/r1'
  export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
  source "$root/hooks/pre-checkout"
  helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
  [[ -x "$helper" ]] || exit 11
  source "$root/hooks/pre-exit"
  [[ ! -e "$helper" ]] || exit 12
)
# Caller native skip is not undone by default plugin checkout=true.
(
  export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true BUILDKITE_SKIP_CHECKOUT=true
  source "$root/hooks/pre-checkout"
  [[ "$BUILDKITE_SKIP_CHECKOUT" == true ]]
  source "$root/hooks/pre-exit"
)
for bad in \
  'BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=invalid' \
  'BUILDKITE_REPO=https://wrong.example/v1/git/acme/fixture.git' \
  'BUILDKITE_BRANCH=main' \
  'BUILDKITE_COMMIT=HEAD' \
  'TRUNK_BUILDKITE_OIDC_AUDIENCE=https://other.example/v1/git/buildkite'; do
  if (export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true; eval "export $bad"; source "$root/hooks/pre-checkout") >/dev/null 2>&1; then
    echo "unexpected positive pre-checkout for $bad" >&2
    exit 3
  fi
done
# Exact HTTPS DNS origin only: reject userinfo, explicit port, ambiguous
# labels, query parameters, cleartext HTTP, and IP literals.
for malformed in \
  'https://operator@eng302-preview.example.test/v1/git/acme/fixture.git' \
  'https://eng302-preview.example.test:443/v1/git/acme/fixture.git' \
  'https://eng302..example.test/v1/git/acme/fixture.git' \
  'https://eng302-preview.example.test/v1/git/acme/fixture.git?query=1' \
  'http://eng302-preview.example.test/v1/git/acme/fixture.git' \
  'https://127.0.0.1/v1/git/acme/fixture.git'; do
  if (
    export TRUNK_BUILDKITE_GIT_REMOTE="$malformed"
    export BUILDKITE_REPO="$malformed"
    export TRUNK_BUILDKITE_OIDC_AUDIENCE="${malformed%/v1/git/*}/v1/git/buildkite"
    export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
    source "$root/hooks/pre-checkout"
  ) >/dev/null 2>&1; then
    echo "Accepted invalid approved remote: $malformed" >&2
    exit 13
  fi
done
[[ "$(wc -l < "$CALLS")" == 5 ]] ||
  { echo 'invalid Git requests must not request OIDC' >&2; exit 14; }
[[ ! -s "$AMBIENT_CALLS" ]] ||
  { echo 'ambient helper must never be used for pinned remote' >&2; exit 15; }

echo 'PASS: default/no-source checkout, scoped ambient helpers, two OIDC credentials per job, Preview pinning, malformed origins, legacy refs, job-local cleanup and fail-closed options'
