# Morphir CLI

The CLI discovers Morphir workspaces, resolves TOML configuration, runs Scheme/IR pipelines and publishes artifacts through a host adapter.

## Run from this repository

On a fresh MoonBit installation, initialize the dependency registry first:

```sh
mise exec -- moon update
```

```sh
mise exec -- moon run apps/morphir --target native -- run path/to/workspace --all
mise exec -- moon run apps/morphir --target js -- workspace path/to/workspace --json
```

Or build and run a standalone executable:

```sh
mise exec -- moon build apps/morphir --target native --release
./_build/native/release/build/morphir/morphir/morphir.exe run path/to/workspace --all
```

## npm package

```sh
mise exec -- npm --prefix apps/morphir run build
node apps/morphir/bin/morphir.js --help
node apps/morphir/bin/morphir.js run path/to/workspace --all
```

The package is named `@morphir/morphir`. After installing a packed or published package, invoke `morphir`. Installation does not require the MoonBit toolchain.

## WASM and WASM-GC

```sh
mise exec -- moon build apps/morphir --target wasm --release
node pkgs/morphir-host/runners/wasm.mjs \
  _build/wasm/release/build/morphir/morphir/morphir.wasm run path/to/workspace --all
```

For WASM-GC, change both target/path occurrences from `wasm` to `wasm-gc`. WASI uses only Preview 1 imports and preopens the current directory; discovery cannot ascend outside that preopen. WASM-GC uses the documented `morphir_host_v1` embedding interface. See [host adapters](../../pkgs/morphir-host/README.md) for configuration mounts and runtime details.

## Commands

```sh
morphir workspace [path] --json
morphir project list [path]
morphir project list [path] --frontend scheme --target ir-json --json
morphir project list [path] --target scheme --target ir-json --json-lines
morphir run [path] --project Core
morphir run [path] --project packages/core
morphir run [path] --all
morphir run path/to/file.scm --file
morphir run path/to/source-directory --directory
morphir run [path] --config transforms.scm --backend scheme
morphir run [path] --dry-run
```

Paths are relative to the current directory. Without a selection, the CLI chooses the enclosing member, configured default member, root project or sole member. A workspace with several members and no default requires `--project` or `--all`. A file path selects only that file. A directory within a project's sources selects that directory; `--directory` explicitly selects a directory even if it is a project root.

Options include `--frontend`, `--backend`, `--output`, `--config`, `--json` and `--dry-run`. Dry run resolves scripts and prints planned sources/destinations without reading source contents or publishing outputs. Exit statuses are 0 success, 2 invalid invocation/configuration, 1 execution/publication failure and 130 cancellation.

`project list` lists every discovered project in workspace order, including the enclosing workspace when invoked from a member. A standalone project produces one entry. Each entry has its project name, relative path, effective frontend and target. Target names are the configured backend identifiers from `pipeline.backend`, defaulting to `ir-json`; frontend defaults to `scheme`. Workspace and member Scheme scripts are applied after manifest configuration, and `--config` adds a final script. Listing can report language choices whose compiler plugins are not installed. It reads configuration without reading source contents or publishing artifacts.

For `project list`, `--frontend` and `--target` filter these effective choices using exact, case-sensitive names. Repeated values match any value within that filter; frontend and target filters must both match when combined. Filters do not override configuration. No matches produce an empty list with exit status 0. Invalid project configuration produces diagnostics and exit status 2, including when filters exclude that project. Text output has `NAME`, `PATH`, `FRONTEND` and `TARGET` columns. JSON output contains `projects`, `diagnostics` and `successful`.

Argument parsing uses pinned `Yoorkin/ArgParser` option specifications with a
Morphir wrapper for command context, duplicate policy and structured help. `morphir --help` and command-specific help such as
`morphir toolchain run --help` are generated from those definitions. JSON help keeps
its command/option inventory and adds a `usage` string. Parse failures retain the
JSON or JSON-lines error envelope and exit status 2.

The parser consumes caller-supplied arguments without reading the process
environment or exiting. Native, JS, Wasm and Wasm GC remain supported. The
standalone Wasm executable retains only `wasi_snapshot_preview1` imports;
it does not require additional MoonBit runtime bindings.

Options accept `--name value` and `--name=value`. Project-list frontend/target
filters, pipeline components and execution dependencies retain their order.
Pipeline options keep their existing last-value behavior; execution and toolchain
single-value options reject duplicates. Empty option values remain invalid.
The host and engine still validate option values and execution policies.

For `toolchain run` and `toolchain exec`, everything after `--` is forwarded
unchanged to the child program. Help/output flags, empty arguments, Unicode and
additional `--` tokens in that segment belong to the program. Morphir does not
interpret them. Other commands reject a program-argument segment.

## Structured output

Every command, including help and dry runs, supports `--json` and `--json-lines`. These flags can appear before or after the command and cannot be combined. `--json` emits one JSON document. `--json-lines` emits one JSON object per line, each with a `type` and `data` field. Diagnostics on stderr do not affect JSON parsing on stdout.

```sh
morphir --json project list . --frontend scheme
morphir workspace . --json-lines
morphir run . --all --json-lines
morphir run . --dry-run --json-lines
morphir project list --help --json
```

| Command | JSON Lines record types |
| --- | --- |
| Help | `help` |
| `workspace` | `workspace` metadata, then `project` entries |
| `project list` | `project` entries, `diagnostic` entries, then a `result` summary |
| `run --dry-run` | `boundary` selections, `source` and `destination` paths, then a `plan` summary |
| `run` | `boundary`, `accepted`, `diagnostic`, `artifact` and `committed` entries, then a `result` summary |
| Invocation or configuration failure | `error` |

Project entries contain `name`, `relativePath`, `frontend`, `target` and `error`. A project with invalid configuration has null language fields. Project-list result summaries contain `successful` and `projectCount`; run result summaries contain `successful`, `processed` and `publicationError`. Failed transformations are reported as diagnostics followed by an unsuccessful result. Existing JSON documents for workspace discovery and pipeline execution retain their fields.

## Workspace example

```toml
[workspace]
members = ["packages/*"]
exclude = ["packages/experimental"]
default_member = "packages/core"
out_dir = ".morphir/out"

[frontend]
language = "scheme"

[ir]
format_version = 4
```

A member's `packages/core/morphir.toml`:

```toml
[project]
name = "Core"
source_directory = "src"
```

The CLI also finds `.morphir/morphir.toml` and `.config/morphir/config.toml`. Multiple primary candidates are errors. YAML candidates are detected and reported as unsupported. Legacy `morphir.json` and `morphir-workspace.json` remain supported; canonical configuration takes precedence with a warning.

Configuration layers are defaults, system, global user, workspace primary, member primary, workspace/member user overrides, environment and CLI. Global configuration and shared workspace defaults exclude project identity and workspace-root settings when applied to a member. Tables merge recursively and arrays replace. TOML encoding preserves unknown values semantically, without preserving comments or formatting.

Workspace and project `morphir.config.scm` files supply pipeline configuration and transforms. An explicit `--config` script runs last; explicit CLI frontend/backend choices are reapplied afterward. Scripts cannot access filesystem, processes or network implicitly.

Outputs go to `.morphir/out/<member-path>/compile.dest/<source-stem>.ir.json`. Each source produces an independent distribution. Project-wide linking and dependency resolution are separate compiler work. Supported frontends/backends are `scheme` and `ir-json`; requested unregistered frontends fail explicitly. JSON output supports IR versions 1 through 4 through existing lossless migration codecs. Unsupported layouts and serialization formats fail validation.

Conventional project/module spelling such as `Core` and `Main.scm` is converted to canonical IR names. `project.module_prefix` qualifies modules; `project.exposed_modules` controls module visibility.

No outputs are published if any selected project's transformation fails. A publication I/O failure can leave earlier task destinations committed; the JSON result identifies them. See the host documentation for locking and recovery.

## Ion checkpoints

The `checkpoint` backend runs a typed IR identity pipeline with Ion binary as its
default intermediate file format. Source format and checkpoint format are separate:

```toml
[project]
name = "Pricing"
source_directory = "src"
[frontend]
language = "ir-json"
[pipeline]
backend = "checkpoint"
checkpoint_format = "ion-binary"
```

```sh
morphir run . --frontend ir-json --backend checkpoint --json
morphir run . --frontend ion-binary --backend checkpoint --checkpoint-format ion-text
morphir run . --frontend ion-text --backend checkpoint --checkpoint-format morphir-json
```

`ir-json` reads supported versioned Morphir JSON. `ion-text` selects `.ion` files;
`ion-binary` selects `.ionb` and `.10n` files. Ion sources use the engine's
[`morphir-pipeline-v1` IR-unit envelope](../../pkgs/morphir-engine/data/README.md).
Each unit ID is its source-relative path with the final extension removed, such as
`nested/Main`. Moving or renaming an Ion source requires an explicitly matching
envelope ID. Output suffixes are `.ionb`, `.ion`, or `.json`, respectively, under
the existing `compile.dest` task directory. Checkpoint JSON export writes the
standard current Morphir JSON schema and refuses to discard engine metadata or
additional envelope annotations. Historical JSON export remains available through
the `ir-json` backend and `ir.format_version`.

Checkpoint execution preserves rich Ion metadata and ordered annotations. It
currently rejects configured transforms and `project.exposed_modules`, which
require metadata lineage. Scheme and registered text frontends can also produce
typed IR checkpoints. This source-only path needs no compiler or toolchain
provider and acquires nothing. Existing Scheme/JSON text pipelines retain their
defaults. `pipeline.checkpoint_format` applies to the checkpoint backend;
`ir.format` continues to describe the existing JSON output contract.

Dry-run and execution JSON include `boundaries`, recording selected codec,
profile and byte requirements. Execution adds `artifactDetails` with format,
encoding, byte count and `status: "accepted"`. An accepted artifact passed engine
generation; `committed` separately records destinations actually published.
JSON Lines uses `boundary` and `accepted` records for these additions while
retaining existing `artifact` path records. Human output makes the same
distinction. Failed staging or generation preserves the previous task output.

## Tests

```sh
mise run test:cli
```

Tests run real workspaces on native, Node, standalone WASI and WASM-GC, then pack/install the npm package and repeat the workflow.

## MoonBit tooling

```sh
morphir toolchain info --json
morphir toolchain setup --yes --json-lines
morphir toolchain build ./project --target wasm --json
morphir toolchain run ./project --package main --target wasm --json -- argument
morphir toolchain exec ./script.mbtx --json
```

Use `--home <directory>` or `MORPHIR_MOON_HOME` to select a toolchain explicitly.
Setup reuses matching installations. Network acquisition requires `--yes` and
currently supports macOS arm64 and Linux x64. Native, Node and the Node WASM-GC
runner provide process execution; plain WASI reports it as unsupported. Every
command supports text, JSON and JSON Lines, including errors and help.

`--timeout <milliseconds>` bounds each child operation, from 1 through 600000;
the default is 120000. Arguments after `--` belong to the executed program, so its
`--help` and `--json` flags are preserved. See the host toolchain and embedding
packages for adapters and capability details.

Generate a complete MoonBit library from supported Morphir JSON or Ion input:

```sh
morphir run . --frontend ir-json --backend moonbit --validation source-only
```

Each input gets a project directory with compiler-native source and manifests
and a binary Ion symbol file. JSON reports include the project contract and
membership; JSON Lines reports emit `generated`, `validated` and `published`
events separately. Required builds are the default and require a library
build provider before publication.

For required validation, supply the process provider, helper, matching compiler
installation and offline SDK source explicitly:

```sh
morphir run . --frontend ir-json --backend moonbit --target native \
  --build-provider process --build-helper /path/to/library-build.mjs \
  --home /path/to/moonbit --sdk /path/to/morphir-sdk
```

The npm package includes `build-provider/library-build.mjs`. `--build-node` selects
the Node executable and `--timeout` bounds the process lease in milliseconds.
Equivalent root configuration uses `pipeline.build_provider`, `build_helper`,
`compiler_home`, `sdk`, `build_node` and `build_timeout`. Reports distinguish
`generated` projects, `validated` projects with Ion receipts, and `published`
destinations. JSON retains `committed` destinations for compatibility and adds
`publicationDetails`. Source-only replacement removes old receipts.

Required builds use a private workspace and frozen supplied dependencies. The
provider identifies compiler binaries, matching core, supplied SDK, generated
source and fresh compiler outputs in `build-receipt.ionb`. Every required project
must build and dispose its lease before the publisher takes its lock. A compiler
failure, deadline or cleanup failure preserves previous task output. Generation
does not install a compiler or fetch dependencies, and failed builds never switch
to source-only mode.

The current backend supports concrete nongeneric libraries, including pricing
functions, records, aliases/custom types and audited SDK adapters. See
[generator scope and acceptance](../../pkgs/morphir-moonbit/README.md).

`--component json-identity` inserts a declared Morphir JSON compatibility step.
Repeat `--component` for a sequence of registered components. Dry-run and result
reports list component transports and metadata policies while the engine and
checkpoint formats retain their independent defaults.

## Execute and verify generated libraries

`execute` runs public entries with supported typed boundaries in an E1-generated library. `verify` also
compares each result with the local Scheme evaluator and exits with status 1 on
any mismatch. Select `--target js` (default), `wasm-gc`, `native` (C), or `llvm`.
Native and Node CLI hosts supervise the selected driver using an explicitly
supplied Node helper. The provider probes compile/run capabilities before the
engine plans the calls; missing required targets fail without substitution or
acquisition. Native execution currently uses the POSIX compiler/linker contract
on macOS/Linux. Windows can run JS and Wasm GC; native Windows execution is not
yet advertised by this provider.

```sh
morphir verify model.json --suite calls.ion \
  --execution-helper /path/to/@morphir/morphir/build-provider/execution.mjs \
  --home /path/to/pinned/moon-home \
  --dependency finos/morphir-sdk=/path/to/morphir-sdk \
  --dependency finos/morphir-execution=/path/to/morphir-execution \
  --dependency moonrockz/ion=/path/to/ion \
  --dependency moonbitlang/x=/path/to/x \
  --dependency moonbitlang/async=/path/to/async \
  --log-file execution.ionb --json
```

Supply SDK and execution protocol 0.1.0, Ion 0.3.0, x 0.5.5 and async 0.22.4.
The default compiler/core pin remains `0.10.14+7d59c7ec9`; the C lane forces
`MOONBIT_NEW_NATIVE=0`. Preparation copies and hashes
these explicit dependencies into a frozen workspace; it does not fetch packages.
The driver imports public generated exports and applies their curried arguments
in order. Argument values arrive at runtime through binary Ion files. A process
session can invoke the same executable repeatedly before disposal.

Model JSON remains supported. Select `--model-format morphir-json`, `ion-text`, or
`ion-binary` explicitly, or use `.json`, `.ion`, `.ionb`/`.10n` suffix detection.
For an Ion model, `--unit-id` must match its envelope identity; the default is
`model`. Suite formats are `ion-text`, `ion-binary`, and `json`, selected with
`--suite-format` or the same suffix rules. See the
[invocation profile](../../pkgs/morphir-execution/README.md) for its schema.

`--dry-run` validates the model, public signatures and suite without acquiring a
provider, compiling, publishing, or writing a log file. `--json` emits one result;
`--json-lines` uses the existing CLI event framing. Logs never enter stdout.
Dry-run capability verification is explicitly deferred; an LLVM dry run requires
a declared toolchain pin, while actual execution probes and checks its local
compiler/core/runtime identities before planning.
`execute` and `verify` leave existing generation output untouched. Their execution
workspaces are disposed after calls and evaluator comparisons, including failure.

Optional `--log-file` defaults to binary Ion. `--log-format ion-text`, `json-lines`
and `text` are available. The local adapter retains up to 2,048 observations and
three previous log files. Binary logs include a final bounded stage-metrics record;
duration buckets have upper bounds 0.001, 0.01, 0.1, 1, 10 and 60 seconds, followed
by an overflow bucket. Sink failures and dropped records produce stderr warnings
without changing execution results. Payload capture and network export are not
enabled. Hosts can supply their own observer, clock, sink and lifecycle policy.

Scheme comparison has finite evaluation limits and disables runtime accelerators.
It shares SDK implementations with generated code, so it does not establish
independent SDK conformance. The tests also assert independently chosen expected
values. LLVM scalar execution is verified separately on macOS arm64 with
`0.10.14+6b3b9bf5a-nightly` and its matching LLVM core bundle. Other LLVM hosts
are explicitly unavailable until verified. Upstream Rust evaluator coverage, full failure supervision, verification publication
and native OpenTelemetry collector integration remain open E2 gates. Rich values
are supported by the pricing slice described below.

Run the scalar CLI acceptance with:

```sh
MOON_HOME=/path/to/pinned/moon-home node apps/morphir/scripts/test-execution.js
```

For the LLVM lane, prepare an isolated compiler/core installation, bundle its
LLVM core, and supply `--home` and `--toolchain-pin`. The explicit JSON pin
profile `morphir-toolchain-pin-v1` contains `compilerVersion`, SHA-256
`compilerIdentity`/`coreIdentity`, `platform`, `arch`, `targets: ["llvm"]`, and
`acquisition` with `compilerUrl`, `coreUrl`, `compilerArchiveIdentity` and
`coreArchiveIdentity`. Preserve and verify the acquired archives yourself;
provider helpers never acquire tooling. Generate the pin from prepared local
files with `build-provider/toolchain-pin.mjs <home> <acquisition.json>`.
Keep this home separate from the default installed compiler. LLVM pins select
only `llvm`; pins for JS, Wasm GC or native C must use the stable compiler version.
Mixed stable/nightly target sets and duplicate targets are rejected.

Execution receipts identify source, driver, configured driver, manifest, build,
executable, compiler, core and runtime independently. Native receipts include the
selected C compiler/linker, runtime objects and linked libraries. macOS libraries
in the system shared cache are identified by the OS version rather than a
nonexistent standalone file. Wasm GC uses the packaged, hashed Node runner and
its narrow `morphir_execution_v1` import ABI; unknown imports fail. Runtime and
executable identities are rechecked when invoking.

Trace propagation uses bounded W3C version-00 context, separate from semantic
suite and source identity. The driver validates and echoes the context in its Ion
outcome envelope. Completed call observations correlate target, lease, call and
attempt, with durations measured on the driver's own monotonic clock. Repeated
invocations need distinct, ordered attempts. `--telemetry-adapter local` is the
default; `none` disables logging. An unavailable explicitly named adapter fails
selection. No OpenTelemetry package is imported by portable engine/driver code.

To include the verified LLVM lane in the scalar acceptance gate, set both
`MORPHIR_LLVM_HOME` and `MORPHIR_LLVM_PIN` alongside `MOON_HOME`. The gate runs
selected targets through native, Node and installed npm CLI hosts, and reports
LLVM as not selected when those variables are absent. Task 6 will establish the
required debug/release CI matrix; this optional local gate does not claim it.

Execution defaults to `--build-mode debug`; `--build-mode release` builds and locates
the optimized executable and records its mode. `--comparison exact` is the default.
Use `--comparison approximate --absolute-tolerance 0.000001 --relative-tolerance 0`
to select a tolerance explicitly. Tolerances without approximate selection are
rejected, and signed zero/non-finite bits remain exact under either policy.

The checked-in [pricing suite](../../pkgs/morphir-moonbit/fixtures/execution/pricing-suite.ion)
exercises 32 rich calls. `mise run test:compiler` runs it in debug and release on
available JS, Wasm GC and native targets, plus explicitly supplied LLVM. Its reports
state the shared-SDK Scheme conformance profile. It also verifies Ion extension
round trips, enumerated model errors, typed rejections, and telemetry isolation.
Embedding hosts can opt into redacted payload capture separately from the logging
observer; the CLI leaves capture disabled. Local metric dimensions are capped at
128 series, with overflow counts and no entry/correlation identifiers as labels.
