#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/empty"
cat > "$tmp/bin/buildkite-agent" <<'AGENT'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'oidc request-token --audience https://app.trunk.dev/v1/git/buildkite --claim build_id,pipeline_id' ]] || exit 81
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
# Both modes must work in an empty workspace. Source the hook to emulate
# agent hook environment export; no real Buildkite API or server is mocked here.
cd "$tmp/empty"
for mode in true false; do
  (
    export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT="$mode"
    export BUILDKITE_SKIP_CHECKOUT=false
    source "$root/hooks/pre-checkout"
    [[ "$GIT_CONFIG_COUNT" == 3 && -x "$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper" ]]
    if [[ "$mode" == false ]]; then [[ "$BUILDKITE_SKIP_CHECKOUT" == true ]]; else [[ "$BUILDKITE_SKIP_CHECKOUT" == false ]]; fi
    [[ ! -e .git ]]
    for i in 1 2; do
      output="$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | git credential fill)"
      [[ "$output" == *'username=trunk-byo'* && "$output" == *'password=eyJhbGciOiJSUzI1NiJ9.eyJqb2IiOiJtb2NrIn0.sigmock'* ]]
    done
    helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
    [[ -z "$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/other.git\n\n' | "$helper" get)" ]]
    [[ -z "$(printf 'protocol=https\nhost=other.example\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]]
    source "$root/hooks/pre-exit"
    [[ ! -e "$helper" ]]
  )
done
[[ "$(wc -l < "$CALLS")" == 4 ]]
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
echo 'PASS: no-source/default/native-skip modes, two fresh OIDC credentials per job, wrong origin/path, cleanup and fail-closed options'
