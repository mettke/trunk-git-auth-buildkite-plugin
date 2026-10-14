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
export BUILDKITE_REPO='https://app.trunk.dev/v1/git/acme/fixture.git'
export BUILDKITE_BRANCH='_trunk/candidates/chg_abc123/r1'
export BUILDKITE_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export MOCK_EXPECTED_AUDIENCE='https://app.trunk.dev/v1/git/buildkite'
unset ALLOW_HOST_REGEX TRUNK_BUILDKITE_GIT_REMOTE TRUNK_BUILDKITE_OIDC_AUDIENCE
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
    export TRUNK_BUILDKITE_OIDC_AUDIENCE=https://ignored.example/v1/git/buildkite
    source "$root/hooks/pre-checkout"
    [[ "$TRUNK_BUILDKITE_OIDC_AUDIENCE" == "$MOCK_EXPECTED_AUDIENCE" ]]
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

# A different valid Trunk repository works without a second configured Git
# remote or audience. The job-local helper must be scoped to the new path.
(
  export BUILDKITE_REPO='https://app.trunk.dev/v1/git/another-org/second-repo.git'
  export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
  source "$root/hooks/pre-checkout"
  [[ "$TRUNK_BUILDKITE_OIDC_AUDIENCE" == "$MOCK_EXPECTED_AUDIENCE" ]]
  credential="$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/another-org/second-repo.git\n\n' | git credential fill)"
  [[ "$credential" == *'username=trunk-byo'* ]] || exit 6
  helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
  [[ -z "$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]] || exit 7
  source "$root/hooks/pre-exit"
  [[ ! -e "$helper" ]] || exit 8
)
[[ "$(wc -l < "$CALLS")" == 5 ]] || { echo 'different Trunk repo OIDC request missing' >&2; exit 9; }

# Preview requires an explicit operator-owned hostname pattern, and its
# audience must follow that allowed host rather than a pinned old env value.
(
  export ALLOW_HOST_REGEX='trunk-dashboard-[a-z0-9]+-balearic-labs\.vercel\.app'
  export BUILDKITE_REPO='https://trunk-dashboard-qyni6rzes-balearic-labs.vercel.app/v1/git/acme/fixture.git'
  export MOCK_EXPECTED_AUDIENCE='https://trunk-dashboard-qyni6rzes-balearic-labs.vercel.app/v1/git/buildkite'
  export TRUNK_BUILDKITE_OIDC_AUDIENCE='https://wrong.example/v1/git/buildkite'
  export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
  source "$root/hooks/pre-checkout"
  [[ "$TRUNK_BUILDKITE_OIDC_AUDIENCE" == "$MOCK_EXPECTED_AUDIENCE" ]]
  credential="$(printf 'protocol=https\nhost=trunk-dashboard-qyni6rzes-balearic-labs.vercel.app\npath=v1/git/acme/fixture.git\n\n' | git credential fill)"
  [[ "$credential" == *'username=trunk-byo'* ]] || exit 10
  helper="$TRUNK_BUILDKITE_JOB_HELPER_DIR/credential-helper"
  [[ -z "$(printf 'protocol=https\nhost=app.trunk.dev\npath=v1/git/acme/fixture.git\n\n' | "$helper" get)" ]] || exit 11
  source "$root/hooks/pre-exit"
  [[ ! -e "$helper" ]] || exit 12
)
[[ "$(wc -l < "$CALLS")" == 6 ]] || { echo 'explicit Preview OIDC request missing' >&2; exit 13; }
[[ ! -s "$AMBIENT_CALLS" ]] || { echo 'ambient Git helper used' >&2; exit 14; }

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
  'BUILDKITE_REPO=ssh://app.trunk.dev/v1/git/acme/fixture.git'; do
  if (export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true; eval "export $bad"; source "$root/hooks/pre-checkout") >/dev/null 2>&1; then
    echo "unexpected positive pre-checkout for $bad" >&2
    exit 3
  fi
done
# Reject non-Trunk destinations and malformed URL shapes before helper
# configuration. A permissive-looking Preview regex cannot allow malformed
# URLs, while an anchored regex must not accept a matching hostname substring.
for malformed in \
  'https://operator@app.trunk.dev/v1/git/acme/fixture.git' \
  'https://app.trunk.dev:443/v1/git/acme/fixture.git' \
  'https://app..trunk.dev/v1/git/acme/fixture.git' \
  'https://app.trunk.dev/v1/git/acme/fixture.git?query=1' \
  'https://app.trunk.dev/v1/git/acme/fixture.git#fragment' \
  'http://app.trunk.dev/v1/git/acme/fixture.git' \
  'https://127.0.0.1/v1/git/acme/fixture.git' \
  'https://app.trunk.dev/v1/git/acme/../fixture.git' \
  'https://app.trunk.dev/v1/git/acme/fixture.git/' \
  'https://app.trunk.dev.evil.example/v1/git/acme/fixture.git'; do
  if (
    export BUILDKITE_REPO="$malformed" ALLOW_HOST_REGEX='trunk-dashboard-[a-z0-9]+-balearic-labs\.vercel\.app'
    export BUILDKITE_PLUGIN_TRUNK_GIT_AUTH_CHECKOUT=true
    source "$root/hooks/pre-checkout"
  ) >/dev/null 2>&1; then
    echo "Accepted malformed or unexpected host: $malformed" >&2
    exit 15
  fi
done

preview='https://trunk-dashboard-qyni6rzes-balearic-labs.vercel.app/v1/git/acme/fixture.git'
# A blanket preview exception is never accepted, even when the URL is valid.
if (
  export BUILDKITE_REPO="$preview" ALLOW_HOST_REGEX='.*'
  source "$root/hooks/pre-checkout"
) >/dev/null 2>&1; then
  echo 'Accepted blanket Preview hostname pattern' >&2
  exit 21
fi
# Unconfigured Preview is rejected even when legacy settings claim approval.
if (
  export BUILDKITE_REPO="$preview" TRUNK_BUILDKITE_GIT_REMOTE="$preview"
  export TRUNK_BUILDKITE_OIDC_AUDIENCE='https://trunk-dashboard-qyni6rzes-balearic-labs.vercel.app/v1/git/buildkite'
  unset ALLOW_HOST_REGEX
  source "$root/hooks/pre-checkout"
) >/dev/null 2>&1; then
  echo 'Accepted Preview without ALLOW_HOST_REGEX' >&2
  exit 16
fi

for rejected in \
  'https://trunk-dashboard-qyni6rzes-balearic-labs.vercel.app.evil.example/v1/git/acme/fixture.git' \
  'https://evil-trunk-dashboard-qyni6rzes-balearic-labs.vercel.app/v1/git/acme/fixture.git'; do
  if (
    export BUILDKITE_REPO="$rejected"
    export ALLOW_HOST_REGEX='trunk-dashboard-[a-z0-9]+-balearic-labs\.vercel\.app'
    source "$root/hooks/pre-checkout"
  ) >/dev/null 2>&1; then
    echo "Accepted unanchored Preview hostname: $rejected" >&2
    exit 17
  fi
done
if (
  export BUILDKITE_REPO="$preview" ALLOW_HOST_REGEX='vercel\.app'
  source "$root/hooks/pre-checkout"
) >/dev/null 2>&1; then
  echo 'Accepted substring-only Preview host regex' >&2
  exit 18
fi
[[ "$(wc -l < "$CALLS")" == 6 ]] ||
  { echo 'invalid Git requests must not request OIDC' >&2; exit 19; }
[[ ! -s "$AMBIENT_CALLS" ]] ||
  { echo 'ambient helper must never be used for pinned remote' >&2; exit 20; }

echo 'PASS: native/no-source modes, multiple Trunk repos, exact-host Preview opt-in, derived audience, URL-scoped helpers, malformed hosts, credential isolation and cleanup'
