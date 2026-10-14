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

## Repository and host configuration

Configure the Buildkite pipeline's normal **Repository** setting to the intended
Trunk Git HTTPS remote, for example
`https://app.trunk.dev/v1/git/<org>/<repo>.git`. The plugin reads Buildkite's
existing `BUILDKITE_REPO` and **does not choose, rewrite or validate the
customer's intended repository**. Do not hardcode a second remote in job YAML.
The plugin also does not configure Trunk's BYO Buildkite dispatch or pipeline
binding. A wrong but syntactically valid Trunk repository is an operator
configuration issue; Trunk's signed, historical job/build/pipeline/tenant/repo,
ref and candidate-SHA authorization independently denies unauthorized Git
reads.

Before enabling its job-local helper, `pre-checkout` requires one canonical
lowercase-DNS HTTPS host, no port/userinfo/escape/query/fragment, and the exact
route `/v1/git/<org>/<repo>.git`. **Only `app.trunk.dev` is allowed by
default.** The plugin constructs the OIDC audience solely from that validated
host, as `https://<host>/v1/git/buildkite`. The previous required
`TRUNK_BUILDKITE_GIT_REMOTE` and `TRUNK_BUILDKITE_OIDC_AUDIENCE` job inputs
are obsolete; supplied legacy values are not used to select the remote or
audience.

For an explicitly authorized *internal Preview* job, the trusted Buildkite
operator may additionally configure `ALLOW_HOST_REGEX`, for example:

```sh
# Trusted operator/agent configuration, not unreviewed source-controlled job code.
export ALLOW_HOST_REGEX='trunk-dashboard-[a-z0-9]+-balearic-labs\.vercel\.app'
```

This is a POSIX extended regex evaluated against the **entire already
validated DNS hostname**, never against the full URL or a substring. Use a
narrow exact-host or deployment-specific pattern; do not set `.*`, an
all-host wildcard, or a Production-wide Preview exception. The option is
unset by default and cannot permit cleartext, alternate paths, URL userinfo,
ports or malformed hostnames. It is host protection, **not** a substitute for
Trunk's server-side OIDC, immutable-source, tenant and read-only authorization.
A Preview that has not independently enabled the matching Trunk Git OIDC
audience still fails closed.

The Buildkite job must have a valid public immutable candidate branch
`_trunk/candidates/chg_.../rN` (historical `trunk/candidates/...` is checked
server-side), a full 40-character commit, and a genuine Trunk API-created
Buildkite dispatch. Production Git OIDC remains off unless enabled under its
own server policy; the plugin cannot authorize a pipeline.

On each matching HTTPS credential challenge the helper requests `buildkite-agent oidc request-token --audience ... --claim build_id,pipeline_id`. Tokens are not persisted to Git config, URLs, command arguments or disk. The helper is created with a job-local restrictive permission and pre-exit removes only the matching owned file. Do not install global hooks on a shared queue. Avoid `set -x` around any authentication path.

## Validation and migration

Run `./scripts/validate.sh --expected-commit <FULL_40_CHARACTER_COMMIT_SHA>` from a clean Git checkout of the exact reviewed feature commit. The validator verifies the full HEAD and a clean tracked/staged/untracked working tree **before and after** syntax/security checks, mock OIDC multiple-request checks, ambient Git-helper suppression without global-config mutation, default Production-only host and explicit full-host Preview regex, malformed HTTPS-origin rejection, isolation and no-checkout behavior. Missing or incorrect SHA, an unexpected repository root, Git read failure, or a dirty checkout fails before tests. It does not substitute for a real API-created Buildkite Hosted job with normal native Git checkout at exact HEAD, a separate source-free no-checkout job, fail-closed authorization negatives, real job lifecycle cleanup and Codex/exact-head validation. Those gates must pass before publication/Trunk script retirement.

The temporary v1 URLs in Trunk remain independently managed until consumers—including the active ENG-78 fixture—have migrated. Do not rely on these URLs from this plugin, and do not remove them before the approved retirement stage.
