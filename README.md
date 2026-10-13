# Trunk Git Auth Buildkite Plugin

Buildkite job-scoped Git authentication for an **exact Trunk candidate**. The plugin configures a narrow credential helper before the stock checkout; it never checks out source itself. JWTs are minted on demand from genuine Buildkite job OIDC, and Trunk independently authorizes every Git read against the historical dispatch, binding, repository and immutable candidate. Existing Trunk API, dispatch and revocation controls are not replaced by this plugin.

## Setup

The public release must be pinned by an **exact reviewed commit SHA**, not a moving branch:

```yaml
steps:
  - label: "Trunk candidate"
    command: "git rev-parse HEAD"
    plugins:
      - balearic-labs/trunk-git-auth#<REVIEWED_40_CHAR_SHA>: {}
```

For an agent job that must **not** automatically check out source:

```yaml
steps:
  - label: "No-source job"
    command: 'test ! -d .git && printf "No automatic checkout\\n"'
    plugins:
      - balearic-labs/trunk-git-auth#<REVIEWED_40_CHAR_SHA>:
          checkout: false
```

The plugin option `checkout: false` sets `BUILDKITE_SKIP_CHECKOUT=true` during the agent **pre-checkout** phase. This is distinct from the native Buildkite YAML `checkout.skip: true` or `BUILDKITE_SKIP_CHECKOUT=true`: an existing native skip remains respected regardless of this plugin's default `checkout: true`. The plugin still prepares the credential helper without requiring `.git` or `HEAD`; commands can subsequently make authorized **read-only** Git requests on their own, but do not need to. Checkout disabled is **not** evidence of an exact local HEAD.

Use only supported Buildkite agents with plugin hooks and native `checkout.skip` semantics. Check the exact Hosted agent version and behavior before declaring customer compatibility. `scripts/validate.sh` verifies package/credential-helper logic offline but **does not** prove real Hosted checkout.

## Trusted job configuration

The agent or operator must supply these **trusted** values, not arbitrary source-controlled changes:

- `TRUNK_BUILDKITE_GIT_REMOTE`: exact single HTTPS remote, e.g. `https://app.trunk.dev/v1/git/<org>/<repo>.git`; it must match Buildkite `BUILDKITE_REPO`.
- `TRUNK_BUILDKITE_OIDC_AUDIENCE`: exactly the corresponding origin plus `/v1/git/buildkite`.

The Buildkite job must have a valid public immutable candidate branch `_trunk/candidates/chg_.../rN` (legacy `trunk/candidates/...` remains validated server-side), a full 40-digit exact candidate commit and an actual Trunk API-created Buildkite dispatch. Production OIDC is off by default unless explicitly enabled on the correct server. The plugin is not a mechanism to enable an unauthorized pipeline.

On each matching HTTPS credential challenge the helper requests `buildkite-agent oidc request-token --audience ... --claim build_id,pipeline_id`. Tokens are not persisted to Git config, URLs, command arguments or disk. The helper is created with a job-local restrictive permission and pre-exit removes only the matching owned file. Do not install global hooks on a shared queue. Avoid `set -x` around any authentication path.

## Validation and migration

Run `./scripts/validate.sh --expected-commit <FULL_40_CHARACTER_COMMIT_SHA>` from a clean Git checkout of the exact reviewed feature commit. The validator verifies the full HEAD and a clean tracked/staged/untracked working tree **before and after** syntax/security checks, mock OIDC multiple-request checks, isolation and no-checkout behavior. Missing or incorrect SHA, an unexpected repository root, Git read failure, or a dirty checkout fails before tests. It does not substitute for a real API-created Buildkite Hosted job with normal native Git checkout at exact HEAD, a separate source-free no-checkout job, fail-closed authorization negatives, real job lifecycle cleanup and Codex/exact-head validation. Those gates must pass before publication/Trunk script retirement.

The temporary v1 URLs in Trunk remain independently managed until consumers—including the active ENG-78 fixture—have migrated. Do not rely on these URLs from this plugin, and do not remove them before the approved retirement stage.
