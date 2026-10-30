# Mooncakes release commands

The public release inventory is `scripts/mooncakes-modules.json`. Every module
has an explicit public or excluded disposition. Public modules share one version
and exact internal dependency pins. The CLI module is `finos/morphir`; the npm
package remains `@morphir/morphir`.

Mooncakes consumers require stock MoonBit `0.10.16` or later. Release builds use
the exact compiler pinned in `.config/mise/config.toml`. Before publication,
qualify the packaged candidate with the minimum consumer compiler as well as the
release compiler, including the long-decimal regression.

Use the pinned compiler and its stock core. Keep `MOON_CORE_OVERRIDE` unset.
Release scripts require the default Mooncakes registry. The release workflow runs
publication and the clean consumer on Linux. The private environment requires
filesystem symlink privileges.

## Check a candidate without uploading

After updating module versions and internal pins together, regenerate and commit
the CLI identity in `apps/morphir/cli/release_identity.mbt`. Downstream builds skip build rules, so the generated identity
is shipped as source and validated against the manifest before packaging.

```sh
mise run release:identity -- --json
mise run release:inventory -- --json
mise run test:release
mise run release:check -- --json
mise run release:minimum:setup -- --json
mise run release:plan -- --tag v0.1.0 --sha FULL_COMMIT_SHA --mode dry-run --json
```

Check and plan never read a credential or upload. Public sources, the inventory
and the compiler pin must be clean. Plan additionally requires a clean checkout
and an exact tag/version/SHA match. It saves `.dev/mooncakes-release/plan.json`.
An optional `--output` chooses another file below `.dev/mooncakes-release/`.
Inventory performs the cheap identity and declared-file checks without a build.
The existing CI configuration job always runs it, including README-only changes.
The Linux JS Build leg runs the archive check once after CLI acceptance.

Packaging starts from a Git snapshot containing only the selected public
modules. Each archive must contain its manifest, README, license and required
native assets. A second isolated workspace unpacks only the produced archives
and builds Wasm, Wasm GC, JavaScript and native. Moon children receive an explicit
owned `MOON_WORK`, so an ambient workspace override cannot supply hidden inputs.
Registry executable installation explicitly disables workspace discovery instead
of inheriting the library consumer's workspace.

The plan records the source commit, compiler version, core pin digest and each
module's archive/content hashes, byte length and file count. The plan job retains
the exact qualified ZIPs alongside its plan in the same run/attempt artifact.
The publisher consumes those ZIPs, rather than rebuilding sources from Git.
Missing, changed or redirected archives refuse promotion. It also refuses a
dry-run plan.

Before credentials, `moonx scripts/mooncakes-release.mbtx check-artifacts --json`
checks the retained files against the candidate, stock toolchain and minimum
compiler evidence. It safely extracts the archives into an owned workspace and
requires repackaging to reproduce every planned ZIP checksum. Publication
repeats these checks and uploads from the same extracted sources. This preserves
qualified generated sources as well as ordinary files. The command accepts
`--plan`, defaulting to `.dev/mooncakes-release/plan.json`; JSON mode uses the
documented command-result envelope with package evidence in `result`, child
diagnostics on stderr, syntax status 2 and refusal/failure status 1. Help has no
filesystem or subprocess effects. It never reads credentials or uploads.

Plan also qualifies those same archives with exact stock MoonBit
`0.10.16+b1a0e846e`. The setup command installs it in the new directory
`.dev/mooncakes-release/minimum-toolchain`; it refuses an existing directory and
does not change the release compiler or its pin. It uses the official Unix
installer and reports its SHA-256. Plan verifies the compiler version and every
stock core source byte before creating a private Moon home, fresh dependency
and build caches, and an archive-only workspace. It builds all four targets,
runs Scheme and the long-decimal check on each, then checks native CLI help,
version JSON and a worksheet returning 42. No credential is required.

`plan --minimum-home PATH` selects another installed copy of that exact compiler.
`check --minimum-home PATH` adds the same qualification to a local check.
Relative paths are resolved against `--root`. The default check runs the release
compiler only; plan always requires both compilers. The success receipt at
`.dev/mooncakes-release/minimum.json` binds the candidate SHA and every public
module/version/archive hash, compiler and stock-core identities, targets and
completed checks. Failure retains the checks completed before refusal. The
workflow retains this receipt even on failure, embeds success in the plan and
refuses missing, failed or mismatched evidence before its first upload.

Before issuing a plan, a token-free registry preflight checks every public
module/version. Each must be absent or have a downloaded archive identical to
the candidate. Conflicting or unavailable evidence refuses the plan and leaves
`.dev/mooncakes-release/preflight.json` for diagnosis. The release workflow retains
this evidence even on refusal. The publisher repeats an inventory-wide check
before its first upload and rechecks each module before uploading it.

## Credential ownership and cache isolation

The release job first runs `release:environment -- --scope RUN-ATTEMPT --json`.
It creates a mode-0700 directory under `RUNNER_TEMP`, links only the pinned
compiler's `bin`, `lib`, `include` and optional `share`, tests the toolchain and
exports the private `MOON_HOME` through `GITHUB_ENV`. Registry data, dependency
caches and credentials stay outside the cached compiler installation.

Only the credential creation step receives `MOONCAKES_TOKEN`. Run
`release:credentials -- --scope RUN-ATTEMPT --json` to verify that the registry's
read-only token check reports account `finos`. The helper JSON-escapes the token,
creates `credentials.json` and a scope marker exclusively with mode 0600, and
checks local login metadata with `moon whoami`. It refuses preexisting files.
Authentication failures never retry, and output contains no token or underlying
HTTP exception.

Run `release:credentials:clean -- --scope RUN-ATTEMPT --json` on success or failure
before cache saves or artifact uploads. Cleanup removes only unchanged files
owned by that scope. A changed file is preserved for diagnosis. A final
`release:environment:clean -- --scope RUN-ATTEMPT --json` removes the owned private
home, including any changed job-local credential, without following compiler
symlinks. Both cleanup commands are idempotent. Never cache the private home or
upload it as an artifact.

In Actions, invoke the MoonBit scripts directly after preparing the private home,
as `release.yml` does. `mise run` applies the repository's global `MOON_HOME` and
would replace the private path exported through `GITHUB_ENV`.

## Publication and recovery

Publication requires the repository workflow running on the exact reviewed
release tag and commit. The workflow must verify ordinary main-push CI and fresh
full qualification for that commit before making credentials available.
It separately requires the existing Windows headless CLI qualification. Windows
Workbench package acceptance and macOS headless acceptance cover different hosts.

Merge the reviewed version and implementation PR, wait for its main-push CI, and
run the workflow in dry-run mode before creating the release tag:

```sh
gh workflow run release.yml --ref main -f mode=dry-run
```

After the dry run succeeds and publication is authorized, create the version tag
at the reviewed main commit. A tag push starts publication. A manual publication
must select that same existing tag as the workflow ref:

```sh
gh workflow run release.yml --ref v0.1.0 -f mode=publish
```

There is no arbitrary tag input. A publish dispatch on `main`, a mismatched tag,
an unmerged commit or a different checkout SHA is refused before credentials.
The workflow serializes releases without cancelling an in-progress run.

The CI gate polls at most 20 minutes for the exact successful `ci.yml` main-push
run, then requires its successful `ci-ok` job. The qualification gate reads the
current run's `qualification-SHA` Ion receipt and requires profile
`morphir-ci-qualification-v2`, the exact revision, repository, run ID and attempt,
`macos: "run"`, no reused evidence and success for every current required job.
Missing, skipped, cancelled, failed or stale evidence stops publication. Nightly
results do not substitute for the candidate's release qualification.

```sh
mise run release:publish -- --plan .dev/mooncakes-release/plan.json --json
mise run release:verify -- 0.1.0 --json
```

The publisher visits dependencies before consumers. An existing version is
accepted only when its public registry identity, downloaded archive SHA-256 and
fresh registry index agree with the candidate's planned archive hash. Conflicting
or unavailable evidence stops the release. It never deletes, overwrites or bumps
a published version.

Transient read responses and index visibility delays retry at most six times per
poll, with 1, 2, 4, 8 and 16 second delays. Each network read has a timeout. An
upload runs once; authentication, validation and opaque upload failures stop.
Rerun the identical candidate to verify versions that succeeded before a failure.
Changed source requires a new version.
For operational recovery, start a fresh publish dispatch on the same existing
tag. It obtains fresh qualification and retains earlier run receipts. Rerunning
only the publisher job cannot substitute an earlier attempt's qualification
receipt for the current attempt.

The publisher persists `.dev/mooncakes-release/publication.json` before each
upload and after each outcome. `--report` can choose another file below the same
release directory. The report distinguishes `published`, `verified-existing`,
`failed` and `not-attempted`. A failure prevents consumer uploads. An interrupted
upload retains a failed outcome whose completion has not been verified.

Verification creates a fresh temporary consumer outside any repository workspace
and uses empty dependency/build caches. It resolves all public versions, runs
Scheme evaluation and a long-decimal stock-core regression on all four targets,
checks published `moonx` help/version, installs the native CLI, and verifies help,
version and worksheet result `42`. Its receipt records the candidate, compiler,
resolved modules and actual checks. This is distinct from archive-only builds.
Verification persists `.dev/mooncakes-release/consumer.json` before emitting
success. `--output` can choose another receipt below the release directory.

After the workflow succeeds, verify every module's registry URL and publish the
GitHub release for the existing tag with the reviewed release notes. Report the
workflow, PRs, GitHub release and registry results. Do not overwrite a version to
repair a failed consumer check.

## Machine-readable output

Every command accepts `--json`, including `--help`. It writes one
`morphir/command-result` version `0.1.0` document to stdout. The document contains
`command`, `state`, `exitCode` and `diagnostics`. Success has `result`; failure has
`error: {code, message}` instead. Syntax errors exit 2. Validation and child
failures exit 1. Progress and child diagnostics use stderr. Publishing suppresses
child upload output because it can contain authentication details.

Inventory returns version, public/excluded counts and dependency order. Check
returns inventory and package evidence. Plan returns a
`morphir/mooncakes-plan` version `0.1.0`. Publication reports use
`morphir/mooncakes-publication` and consumer receipts use
`morphir/mooncakes-consumer`, both version `0.1.0`. Help returns `result.help`
without filesystem or subprocess effects. Focused tests exercise explicit
argument arrays, JSON success/failure status and channel separation without a
live credential or upload. `test:release -- --json` delegates JSON presentation
to Moon's test runner.

The workflow helpers share this JSON contract. `workflow --mode dry-run|publish`
validates the actual event context and optionally writes `--github-output`.
`gate-ci --sha SHA` persists `ci-gate.json`, using profile
`morphir/mooncakes-ci-gate`. `gate-qualification --sha SHA --receipt FILE` persists
`qualification-gate.json`, using `morphir/mooncakes-qualification-gate`. Both
profiles have contract version `0.1.0` and accept `--output` below the release
directory. `gate-needs` checks `RELEASE_NEEDS` from Actions and refuses a missing
or unsuccessful plan, CI, qualification or Windows headless job. These checks
run before credential creation.
