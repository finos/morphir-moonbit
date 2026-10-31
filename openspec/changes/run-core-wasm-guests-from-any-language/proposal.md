# Proposal

## Why

finos/morphir-gleam publishes the Gleam extension `morphir-gleam` 0.4.0 as a core-Wasm guest for the execution
profile `morphir/mep-bytes-v1/v1-draft` (finos/morphir-gleam#23). The MoonBit CLI cannot run it on the
`core-wasm-process` route, for two reasons:

1. **One document only.** The route sends exactly one source document and always sets `languageId: "moonbit"`.
   A Gleam project is a tree of modules under `src/` that import one another. The guest must get the whole tree in
   one `compileModel` request, with the language from its claims.
2. **MoonBit artifacts only.** The route loads only `model.wasm` with a binary Ion `manifest.ion` of schema
   `morphir-assembly-artifact-v1-draft`. That manifest records a MoonBit package graph, compiler version and core
   and SDK digests. A guest written in Rust cannot fill these fields truthfully. The Gleam bundle has no
   `manifest.ion`. It has a release descriptor (`2.0.0-draft.2`) with `runtime: "core-wasm"`, an
   `executionProfile` and the guest's claims.

The worker host change `host-extensions-as-workers` will remove this route later. That change is large and
waits on a new repository. This change is a fast follower: it lets the current route run the Gleam module now,
and it puts the new logic in pure MoonBit code that the worker host can reuse.

## What Changes

Gap 1 comes first. The tasks deliver it before gap 2.

- **Claims before the operation.** Before `compile` or `generate`, the CLI runs a describe-only probe session
  of the pinned guest. The live claims select the language, the source file extensions, the multi-document
  permission, the model tuple and the generate target. The operation session must report the same claims.
- **Model format negotiation.** Without `--model-format`, `compile` offers every model tuple that the CLI
  supports, in order of preference: Ion first, then JSON. The session uses the first tuple that the guest agrees
  on, so a guest that supports only JSON compiles with JSON. Only an empty agreement is
  `extension.tuple_unavailable`. With `--model-format`, the CLI offers only that tuple, and a guest that does not
  claim it is refused with `extension.tuple_unavailable` before the operation session. This replaces the rule on
  main that rich operations offer exactly one tuple with no fallback (design.html, SEL-2).
- **Source trees.** `compile` accepts a directory. The CLI collects the regular files that have an extension the
  selected language claims, in a bounded and sorted snapshot. It sends them as documents with relative URIs and
  no `sources.root`. The URI of each document is its path relative to a source base: the current directory, or
  `--source-base`. Absolute host paths do not enter the request.
- **Tree limits.** At most 1,024 documents, 1 MiB for each file, 2 MiB of source text in total, a depth of 32
  and 16,384 walked entries. Symbolic links and special files are refused. The framed request must still fit in
  4 MiB.
- **Language and target from claims.** The CLI sends the claimed language ID, not `moonbit`. When the guest
  claims more than one language, `--language` selects one. `generate` takes its default target from the claims
  when the guest claims exactly one target. A tree with more than one document needs the claim
  `frontend.multiDocument: true`.
- **Descriptor-pinned modules.** A `core-wasm-process` pin can name a module form artifact: a directory, the
  release descriptor file name and digest, the module digest, and the expected extension ID and version. No
  `manifest.ion` is needed. The existing assembly form (`model.wasm` and `manifest.ion`) keeps working with no
  change to its pins.
- **Integrity without the MoonBit manifest.** For a module form artifact, the pinned digests are the trust
  root. The CLI checks the descriptor: schema, identity, a single matching `core-wasm` artifact, the execution
  profile and its digest, and every `critical` member. The Node host checks the module against the profile
  itself: only the three `morphir_bytes_v1` imports with their exact signatures, an exported `handle: () -> i32`
  and one defined, unshared memory of at most 4,096 pages. The descriptor claims must equal the live claims.
- **Acceptance with the real module.** A qualification task runs the released `morphir-gleam` 0.4.0 module, or a
  build from a pinned finos/morphir-gleam commit, through the npm and native CLI. It compiles a Gleam source tree
  with cross-directory imports and generates Gleam from the result.

## Capabilities

### New Capabilities

- `extensions/claim-selection`: the probe session; how the live claims select language and target; how the CLI
  offers model tuples in preference order and uses the first agreed tuple, or only the tuple that
  `--model-format` requires; and how claims must stay the same across the probe and the operation.
- `extensions/source-documents`: how `compile` turns a file or a directory into MEP source documents: URIs,
  ordering, limits, encoding and the multi-document permission.
- `extensions/core-wasm-modules`: how a core-Wasm module without a MoonBit manifest is pinned, checked against its
  release descriptor and against the execution profile, and run.

### Modified Capabilities

None. `openspec/specs/` holds no main specs yet. `host-extensions-as-workers` defines
`extensions/extension-invocation` and `extensions/wasm-workers` but is not archived. This change does not edit
them. Its requirements are written so that the worker host can keep them (see design.html, "Relation to the
worker host").

## Beads

- **Tracked by**: `morphir-ukvn.5.64.37`
- **Related**:
  - `morphir-ukvn.5.64` (parent: the MoonBit CLI becomes the primary Morphir CLI)
  - `morphir-ukvn.5.64.36` (`host-extensions-as-workers`; its groups 6 and 9 replace this route and should reuse
    the source collector, the claim selection and the descriptor decoder from this change)
  - `morphir-ukvn.5.64.28` (Gleam compile, generate and roundtrip; it can use this route as its provider)
  - `morphir-ukvn.5.64.30` (installed native qualification; not changed, installed selection stays out of scope)
  - `morphir-ukvn.5.64.34` (`acquire-extensions-from-repositories`, draft; installation of core-Wasm bundles from
    repositories belongs there, not here)
  - `morphir-ukvn.1.4` (moving the Gleam extension to finos/morphir-gleam)
- **Related outside beads**:
  - finos/morphir-gleam#31 (host test: the host offers the Ion tuple first and the JSON tuple second, and the
    `morphir-gleam` 0.4.0 guest agrees on JSON and compiles)
  - a matching MEP text change to `spec/mep/model-transport.md` in finos/morphir, proposed separately; this change
    does not edit finos/morphir

## Impact

- **Code:** `apps/morphir/cli/extension.mbt` (pin forms, probe session, compile parameters, the model tuple
  offer in `extension_messages` and the agreement check), a new portable
  source-tree collector that `extism.mbt` can also use, the claims decoder in `pkgs/morphir-host/worker`
  (multi-document claim), a release descriptor decoder, `apps/morphir/build-provider/extension.mts` (module form
  staging), and `pkgs/morphir-host/embedding` (`node-mep-cli`, `node-mep-stdio`, `node-mep-worker`,
  `mep-adapter`, `wasm-memory`). The twelve-module host closure keeps the same file names.
- **Pins:** assembly form pins stay valid. Pins must be written again after the embedding host is rebuilt, as
  today.
- **Users:** a `compile` without `--model-format` now offers both model tuples. With a guest that claims Ion,
  such as the MoonBit guest, it still gives Ion. With a guest that claims only JSON, it now runs with JSON instead
  of failing with `extension.tuple_unavailable`. An explicit `--model-format` behaves as today.
  `apps/morphir/docs/extension.md` changes its "no fallback" text to this rule. `compile` accepts directories. A file whose extension the guest does not claim is refused with
  `extension.source_required`, not with `extension.moonbit_source_required`. Exit status 2 does not change.
- **Qualification:** one new opt-in task, `test:portable-mep-gleam`. It is not added to routine PR CI and adds no
  macOS or Windows job.
- **Other repositories:** none are changed. The acceptance task reads the finos/morphir-gleam release
  `extension/gleam/v0.4.0` (not published at the time of writing) or builds the module from a pinned commit.
