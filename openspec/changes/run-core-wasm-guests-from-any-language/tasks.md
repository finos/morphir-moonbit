# Tasks

Groups 1 and 2 deliver gap 1 (document trees). Group 3 delivers gap 2 (non-MoonBit guests). Group 4 runs the real
Gleam module through both.

## 1. Claims and probe session on the core-Wasm route (morphir-ukvn.5.64.37.1)

- [ ] 1.1 Decode `capabilities.frontend.multiDocument` into `Claims` in `pkgs/morphir-host/worker` (INT-2); verify
  new cases in `claims_test.mbt` and that the existing worker tests still pass on all four targets
- [ ] 1.2 Add a describe-only probe session before `compile` and `generate` in `apps/morphir/cli/extension.mbt`,
  decoded with `Claims::from_describe` (SEL-1); verify the "Probe session before an operation" scenarios with the
  stand-in runtime in `apps/morphir/scripts/test-extension-provider.ts`
- [ ] 1.3 Select the language and file extensions from the claims, add `--language`, and remove the fixed
  `moonbit` language and `.mbt` check (SEL-3); verify the "Language from claims" scenarios in
  `extension_wbtest.mbt`
- [ ] 1.4 Refuse unclaimed operations and unclaimed targets before the operation session, and take the default
  target from the claims (SEL-3); verify the "Operations from claims" and "Generate target from claims" scenarios
- [ ] 1.5 Replace the one-tuple offer in `extension_messages` (`apps/morphir/cli/extension.mbt`, "offer exactly the
  selected tuple: there is no silent codec fallback"): without `--model-format`, offer every supported compile
  tuple with Ion first; with `--model-format`, offer only the required tuple; for `generate`, offer the envelope's
  tuple first, then the tuples that the CLI can convert to; select the tuple from the probe claims and refuse an
  empty selection before the operation session (SEL-2, SEL-4); verify the "Offer every supported model tuple",
  "Negotiated model tuple", "Required model tuple" and "Generate offer from the envelope" scenarios with the
  stand-in runtime, and that the MoonBit guest still agrees on Ion
- [ ] 1.6 Accept an `initialize` agreement only when it holds offered tuples in offer order, use the first agreed
  tuple, and fail with the new code `extension.agreement_mismatch` (exit 1) when it is not the tuple selected from
  the probe claims, keeping `extension.claims_changed` first when the claims also differ (SEL-2); verify the
  "Session uses the first agreed tuple" scenarios and that the report records the agreed tuple
- [ ] 1.7 Add the model conversion to the host library `pkgs/morphir-host`, with the engine codec registry
  (`pkgs/morphir-engine/data/registry.mbt`) and no other converter (SEL-4, A to C): JSON to Ion always lossless,
  Ion to JSON with a loss check that names each dropped kind (`metadata`, `provenance`, `annotations`) and refuses
  with `data.lossy_conversion` unless loss is allowed, the same `modelId`, the revision `sha256:<lowercase hex>` of
  the converted payload, and the conversion record value; verify unit tests for both directions, each dropped kind,
  a lossless Ion model, the revision text and a deterministic second run, on all four targets, and the "One
  conversion in the host library" scenario
- [ ] 1.8 Use the host conversion in `morphir extension generate` before the operation session, and add the flag
  `--allow-model-loss` through the command-line parsing library, scoped to that one command (SEL-4, B and D):
  without the flag a lossy conversion exits 2 with `data.lossy_conversion`, `committed: []` and a message that names
  the flag; with the flag the command exits 0, writes one stderr warning for each dropped kind, and the JSON report
  has `conversion: {from, to, dropped}`; verify the "Generate offer from the envelope", "Host conversion for
  generate", "Identity of a converted model", "Conversion follows the loss rules", "Explicit permission to lose
  model data" and "Report records the conversion" scenarios with the stand-in runtime, in default and `--json`
  mode, with stdout parseable and warnings only on stderr
- [ ] 1.9 Write `mep/conversion.json` next to the guest's artifacts in the same publication, keep the guest's
  retention sidecars as returned, and refuse a guest artifact at `mep/conversion.json` with
  `extension.result_invalid`, exit 1, with or without a conversion (SEL-4, E); verify the "Conversion record" and
  "Reserved conversion record path" scenarios, and that no output directory exists after the refusal
- [ ] 1.10 Require the operation session's claims to equal the probe's and add the `selection` object to the
  report; verify the "Claims stay the same across sessions" and "Report records the selection" scenarios, and
  that the existing report fields of `test:portable-mep-cli` are unchanged
- [ ] 1.11 Document the probe session, `--language`, claim-driven targets and the new refusal codes, including
  `extension.agreement_mismatch`, in `apps/morphir/docs/extension.md`; replace its "There is no fallback between
  them" and "return the offered tuple" text with the SEL-2 rule (preference order, first agreed tuple,
  `--model-format` requires one tuple), and its rule that `generate` sends the envelope unchanged with the SEL-4
  conversion, including `--allow-model-loss`, its warnings, the `conversion` report object, and the content and
  reserved path of `mep/conversion.json`; verify the documented MoonBit commands run as written

## 2. Source trees as relative-URI documents (morphir-ukvn.5.64.37.2)

- [ ] 2.1 Add a portable source collector with a typed refusal (SRC-2): claimed extensions, language ID, source
  base and limits in, sorted documents out; verify unit tests for ordering, limits, links, special files, UTF-8
  and duplicate URIs
- [ ] 2.2 Implement URI construction relative to the source base with RFC 3986 segment encoding, `--source-base`
  and the unchanged single-file rule (SRC-1, SRC-3); verify the "Relative document URIs", "Safe URI segments" and
  "Single file input" scenarios
- [ ] 2.3 Use the collector for `compile` with a directory input and gate more than one document on the
  multi-document claim; verify the "Directory input", "Deterministic order", "Multi-document permission" and
  "Context digest unchanged" scenarios
- [ ] 2.4 Apply the tree limits and keep the 4 MiB framed request check last; verify the "Tree limits" scenarios
  with generated trees in a temporary directory
- [ ] 2.5 Move `extism_sources` in `apps/morphir/cli/extism.mbt` to the collector with `python` and `.py`, with no
  change of behavior or error codes; verify `extism_wbtest.mbt` and `test-extism.mts` pass unchanged
- [ ] 2.6 Document directory input, the source base, the limits and the advice to name `src` from the project
  directory in `apps/morphir/docs/extension.md`; verify the examples with the stand-in runtime

## 3. Descriptor-pinned core-Wasm modules (morphir-ukvn.5.64.37.3)

- [ ] 3.1 Decode the module form pin next to the assembly form, with exact field sets (PIN-1); verify the "Two
  artifact forms" scenarios and that every existing pin fixture is still accepted
- [ ] 3.2 Add a pure release descriptor decoder to `pkgs/morphir-host/worker` for schema `2.0.0-draft.2`: identity,
  the single matching `core-wasm` artifact, the execution profile and the critical members (INT-1); verify the
  "Descriptor content" and "Critical members" scenarios with unit tests
- [ ] 3.3 Read the descriptor in the CLI with a 1 MiB bound and check its digest before decoding; verify the
  "Descriptor integrity" scenario
- [ ] 3.4 Stage the descriptor and the module in `apps/morphir/build-provider/extension.mts` through no-follow,
  digest-checked copies with the 128 MiB module bound, and start the host with `--module FILE`; verify the
  "Verified staging" scenarios in `test-extension-provider.ts`
- [ ] 3.5 Add the `--module FILE` form to `node-mep-cli`, `node-mep-stdio` and `node-mep-worker`, and the
  structural profile check to `wasm-memory.mts` and `mep-adapter.mts` for both forms (INT-1); verify the "Execution
  profile structure" scenarios with crafted modules in `pkgs/morphir-host/embedding/test`, and that the MoonBit
  guest still loads
- [ ] 3.6 Compare descriptor claims with the probe claims and pin identity with live identity, and report the
  descriptor facts as claims (INT-2); verify the "Descriptor claims equal live claims", "Claims are not authority"
  and "Same session behavior for both forms" scenarios
- [ ] 3.7 Document the module form pin, what it checks instead of the MoonBit manifest, and the claim-only origin in
  `apps/morphir/docs/extension.md`; verify a module form pin written from the documentation is accepted

## 4. Qualify the morphir-gleam 0.4.0 module (morphir-ukvn.5.64.37.4)

- [ ] 4.1 Add the fixture tree `apps/morphir/fixtures/gleam-tree/` with cross-directory imports and one file name
  with a space, and its expected payload for the pinned module digest; verify the fixture compiles with the pinned
  module
- [ ] 4.2 Add `scripts/portable-mep-gleam.mbtx` and the mise task `test:portable-mep-gleam` with the two explicit
  bundle inputs (release directory or pinned-commit build) and no silent choice (ACC-1); verify it fails with a
  clear message when neither input is given
- [ ] 4.3 Run compile (with no `--model-format`, so that it agrees on JSON) and generate through the npm and native
  CLI with the module, and the refusal cases of ACC-1, including an explicit `--model-format ion`;
  verify the evidence in `.dev/portable-mep-gleam`, including the probe time and the compile time
- [ ] 4.4 Get a build-master review of where the qualification task runs (no routine PR CI, no new macOS or
  Windows job); verify the decision is recorded in the pull request
- [ ] 4.5 Record the receipt with the module and descriptor digests and the platform as a comment on the epic
  bead, and add a note to `morphir-ukvn.5.64.28` that this route can serve as its provider; verify both comments
  exist

## Workflow follow-up

- When the release `extension/gleam/v0.4.0` is published, record the expected payload again for the released
  module digest and run task 4.3 with the release directory input.
- When finos/morphir accepts the MEP text change to `spec/mep/model-transport.md` (finos/morphir#1115), link it
  from the epic bead. finos/morphir-moonbit#283 aligns the "Model tuple negotiation" requirement of
  `host-extensions-as-workers` with SEL-2; the SEL-4 conversion is an open question in that change. The
  conversion is in `pkgs/morphir-host` so that the worker host and the browser host can call it; propose the
  matching update to `host-extensions-as-workers` in its own change.
- Implement on the MoonBit toolchain 0.10.18 with `moonbitlang/async` 0.22.7 (branch
  `DamianReeves/async-0-22-7`); add no 0.10.17 pins.
- Archive the change after review, as `openspec/config.yaml` describes, and settle the source-selection overlap
  with `host-extensions-as-workers` at that time.
