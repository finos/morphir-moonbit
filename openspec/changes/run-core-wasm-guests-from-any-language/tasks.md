# Tasks

The worker host on main (finos/morphir-moonbit#276 to #280, #284) already does part of this change. A task marked
`[x]` is done on main at `af16f0be`, and the named test proves it. The open tasks are what is still to do. The
table "Scope after the worker host" in design.html maps every requirement to its evidence on main or to its task,
and says why tasks were removed. Group 5 applies the answers to the open questions FIT-1 to FIT-5 of design.html.

Group 1 delivers the claim selection and the `generate` conversion. Group 2 delivers source trees. Group 3 delivers
the remaining descriptor checks. Group 4 runs the real Gleam module through all of them.

## 1. Claims, tuple selection and conversion (morphir-ukvn.5.64.37.1)

- [x] 1.1 Decode `capabilities.frontend.multiDocument` into `Claims` in `pkgs/morphir-host/worker` (INT-2). Done on
  main: `pkgs/morphir-host/worker/claims.mbt:133-160`; test `claims read the frontend capability flags; an absent
  flag is false` (`claims_test.mbt:215`)
- [x] 1.2 Run a describe-only probe before `compile` and `generate` and decode the claims with
  `Claims::from_describe` (SEL-1). Done on main: `apps/morphir/cli/extension.mbt:1409-1416`; tests `compile on the
  model line publishes the model and reports the session` (`extension_session_wbtest.mbt:362`, method order) and
  `probe of a guest that does not describe: describe_failed and no claims` (`host_driver_test.mbt:127`). The
  refusal code of a failed probe is FIT-1 (task 5.1)
- [ ] 1.3 Select the language from the claims (SEL-3): add `--language` through the command-line parsing library,
  refuse several claimed languages without it with `extension.language_required` (exit 2, names the languages),
  refuse an unclaimed language with `extension.capability_unavailable`, and collect only the file extensions of the
  selected language. Replace the first-covering-language rule of `extension_language`
  (`apps/morphir/cli/extension.mbt:428`) and the all-languages list of `extension_claimed_extensions` (`:412`);
  verify the "Language from claims" scenarios in `extension_wbtest.mbt` and `extension_session_wbtest.mbt`
- [ ] 1.4 Add tests for the target selection that `extension_target` (`apps/morphir/cli/extension.mbt:789`)
  already does (SEL-3): several claimed targets without `--target` are refused, and an unclaimed `--target` exits 2
  with `extension.capability_unavailable` and starts no operation session; verify the "Unclaimed target" scenario
  (the default target is proved by `an unsuccessful answer and a failed shutdown publish nothing`,
  `extension_session_wbtest.mbt:1144`)
- [x] 1.5 Offer every supported compile tuple, Ion first, use the first agreed tuple, and offer only the required
  tuple with `--model-format` (SEL-2). Done on main (finos/morphir-moonbit#284): `extension_compile_offer`
  (`apps/morphir/cli/extension.mbt:607`), `Offer::select` and `ModelOperation::host_tuples`
  (`pkgs/morphir-host/worker/negotiation.mbt:59-110`); tests `an operation that the extension does not claim is
  refused before any call` (`extension_wbtest.mbt:386`), `model tuple negotiation: the CLI offers Ion, then JSON,
  and a JSON-only guest compiles with JSON` (`extension_session_wbtest.mbt:499`) and `required model tuple:
  --model-format json offers only JSON, which an Ion-only guest refuses` (`extension_session_wbtest.mbt:540`)
- [ ] 1.6 Name the claimed tuples in the `extension.tuple_unavailable` message of `Offer::select`
  (`pkgs/morphir-host/worker/negotiation.mbt:97-103`) for the default and the required offer (SEL-2); verify the
  "Guest that claims no offered tuple" and "Explicit Ion with a JSON-only guest" scenarios, and that the worker
  tests still pass on all four targets
- [ ] 1.7 Replace the one-tuple offer of `extension_generate_offer` (`apps/morphir/cli/extension.mbt:631`, "the
  host does not convert a model to another tuple"): offer the envelope's tuple first, then the tuples that the host
  library can convert the model to without loss, in host order, then the tuples that it can reach only with loss,
  in host order; select the first offered tuple that the probe claims, and refuse an empty selection with
  `extension.tuple_unavailable` before the operation session (SEL-2, SEL-4; lossless preference decided by Damian
  Reeves, 2026-10-31); verify the "Generate offer from the envelope" and "Prefer a lossless conversion" scenarios
  with the in-memory workers of `extension_session_wbtest.mbt`, and a unit test with a host order in which the
  first convertible tuple is lossy and a later claimed tuple is lossless
- [ ] 1.8 Add the model conversion to the host library `pkgs/morphir-host`, with the engine codec registry
  (`pkgs/morphir-engine/data/registry.mbt`) and no other converter (SEL-4, A to C): JSON to Ion always lossless,
  Ion to JSON with a loss check that names each dropped kind (`metadata`, `provenance`, `annotations`) and refuses
  with `data.lossy_conversion` unless loss is allowed, the same `modelId`, the revision `sha256:<lowercase hex>` of
  the converted payload, the `from`, `to` and `dropped` value of the conversion diagnostic, and a loss check that
  the offer of task 1.7 can run for each tuple before the operation session; verify unit tests for both directions,
  each dropped kind, a lossless Ion model, the revision text and a deterministic second run, on all four targets,
  and the "One conversion in the host library" scenario
- [ ] 1.9 Use the host conversion in `morphir extension generate` before the operation session, and add the flag
  `--allow-model-loss` through the command-line parsing library, scoped to that one command (SEL-4, B and D):
  without the flag a lossy conversion exits 2 with `data.lossy_conversion`, `committed: []` and a message that names
  the flag; with the flag the command exits 0, writes one stderr warning for each dropped kind, and the JSON report
  has `conversion: {from, to, dropped}`; verify the "Host conversion for generate", "Identity of a converted
  model", "Conversion follows the loss rules" and "Explicit permission to lose model data" scenarios with the
  in-memory workers, in default and `--json` mode, with stdout parseable and
  warnings only on stderr
- [ ] 1.10 Add the `extension.model_converted` diagnostic to the diagnostics of `morphir extension generate` when a
  conversion runs: severity `info`, a message that names both tuples, and `data` with exactly `from`, `to` and
  `dropped`, with `profile`, `codec`, `revision` and `payloadSha256` in `from` and `to`; write it as one stderr
  line through the existing diagnostic output; make `result.conversion` the same value; write no file for the
  conversion in the output folder and keep the guest's retention sidecars as returned (SEL-4, E; decided by Damian
  Reeves, 2026-10-31); verify the "Conversion diagnostic", "Conversion diagnostic data", "Conversion reported on
  stderr, not in the output" and "Report records the conversion" scenarios with the in-memory workers, in default
  and `--json` mode: the exact `data` members, `dropped: []` without the flag, the diagnostic after a guest failure,
  one stderr line, stdout parseable, and an output folder with only the guest's paths
- [ ] 1.11 Add the `selection` object to the report: the language ID, the source file extensions, the model tuple
  or target, and the probe outcome; verify the "Report records the selection" scenario and that the existing
  report fields of `extension_session_wbtest.mbt` are unchanged
- [ ] 1.12 Document in `apps/morphir/docs/extension.md`: `--language` and `extension.language_required`, the
  `selection` report object, the tuples in the `extension.tuple_unavailable` message, and the SEL-4 conversion in
  place of "Generate on the model line offers and sends the envelope's own tuple" (the offer, `--allow-model-loss`,
  its warnings, the `conversion` report object, and the `extension.model_converted` diagnostic and its `data`
  members). The
  probe, the preference order and `extension.agreement_mismatch` are documented on main already; verify the
  documented commands run as written

## 2. Source trees as relative-URI documents (morphir-ukvn.5.64.37.2)

- [ ] 2.1 Give `extension_sources` (`apps/morphir/cli/extension.mbt:509`) the typed refusals and the order of the
  spec (SRC-2): `extension.source_required` for no document, `extension.resource_limit` with the limit name
  (`documents`, `fileBytes`, `totalBytes`, `depth`, `entries`) and a new 1 MiB bound for one file,
  `extension.invalid_source_path` with the relative path for a link, a special file or a duplicate URI,
  `extension.invalid_source_encoding` with the URI for text that is not UTF-8, and documents sorted by the whole
  URI in byte order instead of by name in each directory; keep the 4 MiB framed request check of `Call::make`
  (`pkgs/morphir-host/worker/negotiation.mbt:320-337`) last; verify the updated tests in `extension_wbtest.mbt`
  ("Tree limits", "Links and special files", "UTF-8 source text" and "Deterministic order" scenarios) with
  generated trees in a temporary directory
- [ ] 2.2 Make each URI relative to the source base, add `--source-base` through the command-line parsing library,
  and encode each segment as an RFC 3986 path segment instead of refusing names with `:` or `\` (SRC-1, SRC-3);
  keep the single-file rule of `extension_document_uri` (`apps/morphir/cli/extension.mbt:393`) without
  `--source-base`; verify the "Relative document URIs", "Safe URI segments" and "Single file input" scenarios
- [x] 2.3 Accept a directory for `compile` and refuse more than one document without the multi-document claim.
  Done on main: `extension_sources` (`apps/morphir/cli/extension.mbt:509-605`) and `extension_document_count`
  (`:456`); tests `compile selects sources by the claimed file extensions and sends the claimed language`
  (`extension_wbtest.mbt:240`) and `Python 0.4.1 with two modules: a frontend without multiDocument is refused`
  (`extension_session_wbtest.mbt:588`)
- [ ] 2.4 Add tests that two compiles of the same tree give byte-identical `compileModel` requests, and that the same
  package and options with different trees give the same `contextDigest` (the digest code is
  `extension_compile_params`, `apps/morphir/cli/extension.mbt:853-863`); verify the "Same tree twice" and "Same
  options, different trees" scenarios
- [ ] 2.5 Document the source base, the URI encoding, the limits and their codes, and the advice to name `src`
  from the project directory in `apps/morphir/docs/extension.md` ("What one command does", step 4); verify the
  examples with the in-memory workers

## 3. Descriptor checks for WASM modules (morphir-ukvn.5.64.37.3)

- [ ] 3.1 Check the content of a pinned release descriptor in `extension_descriptor`
  (`apps/morphir/cli/extension.mbt:1098`), or in a pure decoder in `pkgs/morphir-host/worker` that the CLI calls
  (INT-1): `schemaVersion` `2.0.0-draft.2`, the descriptor `extensionId` and `version` against the live claims, a
  single matching artifact with a `filename` that has no path separator, its runtime and `executionProfile`
  against the pin's runtime, and every `critical` member, refusing an unknown one by name; verify the "Descriptor
  content" and "Critical members" scenarios with unit tests and the existing `a bad descriptor is refused before
  any worker starts` (`extension_session_wbtest.mbt:1040`)
- [x] 3.2 Read the descriptor with a 1 MiB bound and check its digest before decoding it, before any worker starts.
  Done on main: `apps/morphir/cli/extension.mbt:1098-1120`; test `a bad descriptor is refused before any worker
  starts` (`extension_session_wbtest.mbt:1040`). The code (`extension.digest_mismatch`) is FIT-1
- [x] 3.3 Compare the descriptor claims with the probe claims before the operation session (INT-2). Done on main:
  `extension_descriptor_matches` (`apps/morphir/cli/extension.mbt:1155`); test `descriptor claims that differ from
  the live describe exit 2` (`extension_session_wbtest.mbt:1001`)
- [ ] 3.4 Report the descriptor digest, the module digest and the descriptor `gitCommit` under the report's
  `worker` object with `origin: "claimed"` (INT-2); verify the "Report origin" scenario and that the existing
  `worker` fields are unchanged
- [ ] 3.5 Document the descriptor content checks and the claimed origin in `apps/morphir/docs/extension.md` ("The
  pin"); verify a pin and descriptor written from the documentation are accepted

## 4. Qualify the morphir-gleam 0.4.0 module (morphir-ukvn.5.64.37.4)

- [ ] 4.1 Add the fixture tree `apps/morphir/fixtures/gleam-tree/` with cross-directory imports and one file name
  with a space, and its expected payload for the pinned module digest; verify the fixture compiles with the pinned
  module
- [ ] 4.2 Add `scripts/portable-mep-gleam.mbtx` and the mise task `test:portable-mep-gleam` with the two explicit
  bundle inputs (release directory or pinned-commit build) and no silent choice (ACC-1); the script writes a
  contract `0.2.0` pin with a `wasm` runtime and the bundle's descriptor; verify it fails with a clear message when
  neither input is given
- [ ] 4.3 Run compile (with no `--model-format`, so that it agrees on JSON) and generate through the npm and native
  CLI with the module, and the refusal cases of ACC-1, including an explicit `--model-format ion`;
  verify the evidence in `.dev/portable-mep-gleam`, including the probe time and the compile time
- [ ] 4.4 Get a build-master review of where the qualification task runs (no routine PR CI, no new macOS or
  Windows job); verify the decision is recorded in the pull request
- [ ] 4.5 Record the receipt with the module and descriptor digests and the platform as a comment on the epic
  bead, and add a note to `morphir-ukvn.5.64.28` that this route can serve as its provider; verify both comments
  exist

## 5. Requirements that do not fit main (morphir-ukvn.5.64.37)

- [ ] 5.1 Apply Damian Reeves's answers to the open questions FIT-1 to FIT-5 of design.html. For each requirement
  that the table "Scope after the worker host" marks as an open question, either rewrite the requirement and its
  scenarios to main's behavior, with the evidence that the table names, or add the task that implements it as
  written. Verify `openspec validate run-core-wasm-guests-from-any-language --strict` and that every requirement
  has evidence or a task in the table

## Workflow follow-up

- When the release `extension/gleam/v0.4.0` is published, record the expected payload again for the released
  module digest and run task 4.3 with the release directory input.
- finos/morphir#1115 (merged) states the offer order and the host conversion for `generateModel` in
  `spec/mep/model-transport.md`; link it from the epic bead. Bead `morphir-hv6m` adds the MCK checks of the
  selection order and the conversion. The conversion is in `pkgs/morphir-host` so that the worker host and the
  browser host can call it. `host-extensions-as-workers` points to SEL-4 of this change for the `generate`
  conversion.
- Implement on the MoonBit toolchain 0.10.18 with `moonbitlang/async` 0.22.7 when that upgrade lands on main;
  add no new 0.10.17 pins.
- Archive the change after review, as `openspec/config.yaml` describes, and settle the source-selection overlap
  with `host-extensions-as-workers` at that time.
