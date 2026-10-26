# Trunk Git Auth Buildkite Plugin

Buildkite job-scoped Git authentication for **Trunk-authorized builds**. The plugin configures a narrow credential helper before the stock checkout; it never checks out source itself. JWTs are minted on demand from genuine Buildkite job OIDC, and Trunk independently authorizes every Git read against the historical dispatch, binding, repository and execution provenance. Existing Trunk API, dispatch and revocation controls are not replaced by this plugin.

## Setup

The public release must be pinned by an **exact reviewed commit SHA**, not a moving branch:

```yaml
steps:
  - label: "Trunk checkout"
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
`https://api.trunk.dev/v1/git/<org>/<repo>.git`. The plugin reads Buildkite's
existing `BUILDKITE_REPO` and **does not choose, rewrite or validate the
customer's intended repository**. Do not hardcode a second remote in job YAML.
The plugin also does not configure Trunk's BYO Buildkite dispatch or pipeline
binding. A wrong but syntactically valid Trunk repository is an operator
configuration issue; Trunk's signed, historical job/build/pipeline/tenant/repo,
execution provenance and token authorization independently denies unauthorized
Git reads.

Before enabling its job-local helper, `pre-checkout` requires one canonical
lowercase-DNS HTTPS host, no port/userinfo/escape/query/fragment, and the exact
route `/v1/git/<org>/<repo>.git`. **Only `api.trunk.dev` is allowed by
default.** The plugin constructs the OIDC audience solely from that validated
host, as `https://<host>/v1/git/buildkite`. The previous required
`TRUNK_BUILDKITE_GIT_REMOTE` and `TRUNK_BUILDKITE_OIDC_AUDIENCE` job inputs
are obsolete; supplied legacy values are not used to select the remote or
audience.

For an explicitly authorized *internal Preview* job, the trusted Buildkite
operator may set a single boolean environment variable:

```sh
# Explicit opt-in for Trunk Preview deployment hosts and stable Change aliases.
export ALLOW_TRUNK_PREVIEW=true
```

With this opt-in, the only additional allowed hostname shapes are
`trunk-[a-z0-9-]+-balearic-labs.vercel.app`,
`trunk-[a-z0-9-]+-trunk-dev.vercel.app`, and the stable Change alias
`trunk-[0-9a-f]{40}.vercel.app` (full hostname matches). The first two
permit lowercase letters, numbers and hyphens but no dot in their variable
part; the unscoped alias requires **exactly 40 lowercase hex characters**.
For the ENG-428 fixture, the pipeline Repository can use its stable API
Change alias across revisions with only `ALLOW_TRUNK_PREVIEW=true`.
Pin the reviewed plugin commit for the job. This is a hardcoded hostname
syntax convention, not a proof of Vercel ownership or a user-supplied regex:
the old `ALLOW_HOST_REGEX` setting is ignored and must be removed. By
default (unset or `false`), only `api.trunk.dev` is allowed; other boolean
values are rejected. The Preview opt-in never loosens HTTPS, URL path,
port, userinfo, query or fragment validation.

This option restricts *where a Buildkite-issued token can be sent*; it
does not prove which Vercel deployment is authoritative. Unscoped 40-hex
aliases are globally claimable: a mistyped or reclaimed configured alias can
receive a genuine job OIDC token. Preview jobs therefore require the operator
to verify control of the Repository hostname before running them. The deployed
Trunk server must still independently authorize the exact job-bound OIDC
audience, historical dispatch, execution provenance and read-only Git
operation; that server check cannot prevent token disclosure to a wrong host.

The plugin imposes no branch, ref, lifecycle or commit-selector authorization
restriction and leaves `BUILDKITE_BRANCH` and `BUILDKITE_COMMIT` unchanged.
Candidate refs (including historical `trunk/candidates/...`), landed target
branches such as `main` or `release/stable`, and other checkout inputs all use
the same credential path. Native Buildkite/Git handles checkout selection;
the server determines whether the token authorizes the read. Successful hook
setup does not prove authorization or successful checkout.

Trunk must still authenticate the genuine job and authorize its exact build,
tenant, repository, binding generation and execution provenance. Authentic
jobs in an authorized build retain read-only access throughout the bound
repository, including other refs/reachable objects; exact intended checkout
is execution integrity, not per-ref confidentiality. Landed dispatch must
retain the actual target branch and frozen intended commit even if the branch
later advances. The plugin neither substitutes a branch head nor disguises
landed execution as candidate context. Server-denied reads remain denied;
the plugin grants no cross-repository, cross-tenant, write or general API
permission. Production Git OIDC remains subject to its own server policy.

On each matching HTTPS credential challenge the helper requests `buildkite-agent oidc request-token --audience ... --claim build_id,pipeline_id`. Tokens are not persisted to Git config, URLs, command arguments or disk. The helper is created with a job-local restrictive permission and pre-exit removes only the matching owned file. Do not install global hooks on a shared queue. Avoid `set -x` around any authentication path.

## Validation and migration

The canonical Git host is now `api.trunk.dev`; `app.trunk.dev` is rejected,
even with `ALLOW_TRUNK_PREVIEW=true`. Update the pipeline Repository setting
to `https://api.trunk.dev/v1/git/<org>/<repo>.git` when adopting this plugin
commit. Its OIDC audience is exactly `https://api.trunk.dev/v1/git/buildkite`.
Explicitly opted-in Preview hosts retain their own host-derived audience.

Run `./scripts/validate.sh --expected-commit <FULL_40_CHARACTER_COMMIT_SHA>` from a clean Git checkout of the exact reviewed feature commit. The validator verifies the full HEAD and a clean tracked/staged/untracked working tree **before and after** syntax/security checks, mock OIDC multiple-request checks, ambient Git-helper suppression without global-config mutation, default Production-only host and explicit boolean opt-in for the fixed Trunk Vercel Preview deployment and stable-alias shapes, malformed HTTPS-origin rejection, isolation, unchanged branch/commit inputs across candidate and landed contexts, and no-checkout behavior. Missing or incorrect SHA, an unexpected repository root, Git read failure, or a dirty checkout fails before tests. It does not substitute for a real API-created Buildkite Hosted job with normal native Git checkout at exact HEAD, a separate source-free no-checkout job, fail-closed authorization negatives, real job lifecycle cleanup and Codex/exact-head validation. Those gates must pass before publication/Trunk script retirement.

The temporary v1 URLs in Trunk remain independently managed until consumers—including the active ENG-78 fixture—have migrated. Do not rely on these URLs from this plugin, and do not remove them before the approved retirement stage.
