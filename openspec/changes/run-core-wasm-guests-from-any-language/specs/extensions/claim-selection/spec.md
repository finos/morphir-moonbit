# Spec Delta

## Purpose

Defines how the portable `core-wasm-process` route reads a guest's live claims before an operation, and how those
claims select the language, model tuple and generate target, so that the CLI holds no list of languages. It also
defines how the host converts the model for `generate` when the guest does not claim the envelope's tuple.

## ADDED Requirements

### Requirement: Probe session before an operation
Before `compile` or `generate` starts its operation session, the CLI SHALL run a describe-only session of the
same pinned guest, with the same pin checks. The CLI SHALL decode the live claims from that answer. A probe that
fails SHALL end the command with the same state and exit status as a failed `describe`, and no operation session
SHALL start.

#### Scenario: Compile reads claims first
- **WHEN** a user runs `morphir extension compile src --package acme/shop --model-format json` with a valid pin
- **THEN** the CLI runs a describe-only session, then an operation session, and the report records both

#### Scenario: Guest exits during the probe
- **WHEN** the guest exits before it answers the probe describe
- **THEN** the command fails with `extension.incomplete_session` and no operation session starts

### Requirement: Language from claims
`compile` SHALL send the language ID that the guest claims, in `languageId` and in each document. When the guest
claims one language, the CLI SHALL use it. When it claims several, `--language` SHALL name one of them. The CLI
SHALL contain no fixed language ID.

#### Scenario: One claimed language
- **WHEN** the guest claims only language `gleam` with extension `.gleam`
- **THEN** the request has `languageId: "gleam"` at the top and in each document

#### Scenario: Several claimed languages without a choice
- **WHEN** the guest claims languages `elm` and `gleam` and the user gives no `--language`
- **THEN** the command exits 2 with `extension.language_required` and names both languages

#### Scenario: Unclaimed language
- **WHEN** the user gives `--language python` and the guest does not claim `python`
- **THEN** the command exits 2 with `extension.capability_unavailable` and no operation session starts

### Requirement: Operations from claims
The CLI SHALL start `compile` only when the guest claims `frontend.compile`, and `generate` only when it claims
`backend.generate`. Otherwise the command SHALL exit 2 with `extension.capability_unavailable` before the
operation session.

#### Scenario: Generate with a frontend-only guest
- **WHEN** a user runs `generate` with a guest that claims only a frontend
- **THEN** the command exits 2 with `extension.capability_unavailable` and no operation session starts

### Requirement: Offer every supported model tuple
When the user gives no `--model-format`, `compile` SHALL offer in `morphir.initialize` every model tuple that the
CLI supports for the operation, in the CLI's order of preference. The first tuple is the default. Today the order
is `morphir-model` with `ion-binary`, then `morphir-ir` with `morphir-json`. The offer SHALL add no wire field to
mark the default.

#### Scenario: Offer order without a model format
- **WHEN** a user compiles with no `--model-format`
- **THEN** the operation session offers the Ion tuple first and the JSON tuple second

### Requirement: Negotiated model tuple
When the user gives no `--model-format`, the CLI SHALL select the first offered tuple that the guest claims for
the operation. A guest that does not claim the default tuple but claims another offered tuple SHALL NOT cause an
error. Only when the guest claims no offered tuple SHALL the command exit 2 with `extension.tuple_unavailable`
before the operation session, and the message SHALL name the claimed tuples.

#### Scenario: JSON-only guest without a model format
- **WHEN** a user compiles with no `--model-format` and the guest claims only `morphir-ir` with `morphir-json`
- **THEN** the session agrees on the JSON tuple, the compile runs and the report records the JSON tuple

#### Scenario: Guest that claims both tuples
- **WHEN** a user compiles with no `--model-format` and the guest claims the Ion and the JSON tuple
- **THEN** the session uses the Ion tuple

#### Scenario: Guest that claims no offered tuple
- **WHEN** the guest claims no compile tuple that the CLI offers
- **THEN** the command exits 2 with `extension.tuple_unavailable` and no operation session starts

### Requirement: Required model tuple
When the user gives `--model-format`, the CLI SHALL offer only that tuple. If the guest does not claim it, the
command SHALL exit 2 with `extension.tuple_unavailable` before the operation session, and the message SHALL name
the tuples that the guest claims. The CLI SHALL NOT use another tuple.

#### Scenario: Explicit Ion with a JSON-only guest
- **WHEN** a user compiles with `--model-format ion` and the guest claims only `morphir-ir` with `morphir-json`
- **THEN** the command exits 2 with `extension.tuple_unavailable` and the message names `morphir-ir` with
  `morphir-json`

#### Scenario: Explicit JSON
- **WHEN** a user compiles with `--model-format json` and the guest claims the JSON tuple
- **THEN** the operation session offers only the JSON tuple and the compile runs

### Requirement: Generate offer from the envelope
`generate` SHALL offer the tuple of its input envelope first, then the other tuple that the host library can
convert the model to. The CLI SHALL select the first offered tuple that the guest claims for
`morphir.backend.generateModel`. Only when the guest claims no offered tuple SHALL the command exit 2 with
`extension.tuple_unavailable` before the operation session.

#### Scenario: Envelope tuple claimed
- **WHEN** a user generates from an Ion envelope and the guest claims the Ion and the JSON generate tuples
- **THEN** the session uses the Ion tuple and the CLI sends the envelope unchanged, with no conversion

#### Scenario: JSON envelope with a guest that claims both tuples
- **WHEN** a user generates from a JSON envelope and the guest claims the Ion and the JSON generate tuples
- **THEN** the session uses the JSON tuple, because the envelope's tuple is first in the offer, and no conversion
  runs

#### Scenario: No tuple that the CLI can send
- **WHEN** the guest claims no generate tuple that the CLI offers for the envelope
- **THEN** the command exits 2 with `extension.tuple_unavailable` and no operation session starts

### Requirement: Host conversion for generate
When the selected tuple is not the envelope's tuple, the CLI SHALL convert the model to the selected tuple before
the operation session and send the converted envelope. This SHALL NOT be an error. A conversion from `morphir-ir`
with `morphir-json` to `morphir-model` with `ion-binary` SHALL always be lossless.

#### Scenario: JSON envelope with an Ion-only guest
- **WHEN** a user generates from a JSON envelope, and the guest claims only `morphir-model` with `ion-binary` for
  generate
- **THEN** the CLI converts the model to the Ion tuple with no loss, the generate runs and exits 0, and the report
  has `conversion.dropped: []`

#### Scenario: Lossless Ion envelope with a JSON-only guest
- **WHEN** a user generates from an Ion envelope with no metadata, provenance or non-profile annotations, and the
  guest claims only `morphir-ir` with `morphir-json` for generate
- **THEN** the CLI converts the model to the JSON tuple, the generate runs and exits 0 with no
  `--allow-model-loss`, and the report has `conversion.dropped: []`

### Requirement: One conversion in the host library
The conversion SHALL be in the host library `pkgs/morphir-host` and SHALL use the engine codec registry
(`pkgs/morphir-engine/data/registry.mbt`). The CLI, the browser host and the worker host SHALL use this conversion
and SHALL NOT have their own converters.

#### Scenario: CLI uses the host library conversion
- **WHEN** the CLI converts an envelope to the JSON tuple for `generate`
- **THEN** the sent payload and revision equal the result of the host library conversion for the same envelope and
  tuple

### Requirement: Identity of a converted model
The converted envelope SHALL keep the `modelId` of the envelope that the user gave. Its `revision` SHALL be
`sha256:` followed by the lowercase hexadecimal SHA-256 digest of the converted payload bytes. The same envelope
and the same selected tuple SHALL give the same converted payload and the same revision. The link to the original
envelope SHALL be in the conversion record, not in the converted envelope.

#### Scenario: Revision of a converted model
- **WHEN** the CLI converts a model with `modelId` `acme/shop` to the JSON tuple
- **THEN** the converted envelope has `modelId` `acme/shop` and `revision` `sha256:<hex>`, where `<hex>` is the
  lowercase SHA-256 digest of the converted payload bytes

#### Scenario: Deterministic conversion
- **WHEN** a user runs the same converting `generate` twice with the same envelope and the same guest
- **THEN** both runs send the same converted payload with the same revision

### Requirement: Conversion follows the loss rules
A conversion from `morphir-model` to `morphir-ir` with `morphir-json` SHALL run only when it drops no metadata,
provenance or annotations, unless the user gives `--allow-model-loss`. Without the flag, a lossy conversion SHALL
fail with `data.lossy_conversion`, exit 2, before the operation session and with `committed: []`. The message SHALL
name `--allow-model-loss`. The code SHALL NOT be `extension.tuple_unavailable`.

#### Scenario: Conversion that would lose data
- **WHEN** a user generates from an Ion envelope with source provenance that Morphir JSON cannot hold, the guest
  claims only the JSON generate tuple, and the user gives no `--allow-model-loss`
- **THEN** the command exits 2 with `data.lossy_conversion`, the message names `--allow-model-loss`, the report has
  `committed: []`, and no operation session starts

### Requirement: Explicit permission to lose model data
`generate` SHALL accept `--allow-model-loss`, which applies only to that command; no configuration file or
environment value SHALL set it. With the flag, a lossy conversion SHALL run, the command SHALL exit 0 when the
generate succeeds, and the CLI SHALL write one stderr warning for each dropped kind (`metadata`, `provenance`,
`annotations`). Without a lossy conversion, the flag SHALL change nothing.

#### Scenario: Lossy conversion with the flag
- **WHEN** a user generates with `--allow-model-loss` from an Ion envelope with metadata and provenance, and the
  guest claims only the JSON generate tuple
- **THEN** the generate runs, the command exits 0, stderr has one warning for `metadata` and one for `provenance`,
  and the report has `conversion.dropped: ["metadata", "provenance"]`

#### Scenario: Flag with no conversion
- **WHEN** a user generates with `--allow-model-loss` and the guest claims the envelope's tuple
- **THEN** no conversion runs, no loss warning is written and the report has no `conversion` object

### Requirement: Report records the conversion
When a conversion runs, the JSON report SHALL add a `conversion` object with `from` (the envelope's tuple), `to`
(the sent tuple) and `dropped` (the kinds of dropped data, empty when the conversion is lossless). When no conversion
runs, the report SHALL have no `conversion` object. Existing report fields SHALL keep their names, types and
meaning.

#### Scenario: Report after a lossless conversion
- **WHEN** a converting generate succeeds in JSON mode with no data dropped
- **THEN** the report has `conversion.from` with the envelope's tuple, `conversion.to` with the sent tuple and
  `conversion.dropped: []`

### Requirement: Conversion record
When a conversion runs, the CLI SHALL publish `mep/conversion.json` with the guest's artifacts. It SHALL hold the
original and converted tuples, the original and converted revisions and payload SHA-256 digests, and the dropped
list, empty without `--allow-model-loss`. The CLI SHALL NOT copy the original model bytes. The guest's own
retention sidecars SHALL stay as the guest returns them.

#### Scenario: Record after a conversion
- **WHEN** a converting generate succeeds
- **THEN** the output has `mep/conversion.json` with both tuples, both revisions, both payload digests and the
  dropped list, and the guest's sidecars are the bytes that the guest returned

#### Scenario: No record without a conversion
- **WHEN** a generate succeeds and the guest claims the envelope's tuple
- **THEN** the output has no `mep/conversion.json`

### Requirement: Reserved conversion record path
The path `mep/conversion.json` SHALL be reserved for the host in the output of `generate`. If a guest returns an
artifact at that path, the command SHALL fail with `extension.result_invalid`, exit 1 and publish no output,
whether or not a conversion runs.

#### Scenario: Guest returns the reserved path
- **WHEN** a stand-in guest returns an artifact at `mep/conversion.json`
- **THEN** the command fails with `extension.result_invalid` and no output directory exists

### Requirement: Session uses the first agreed tuple
The CLI SHALL accept an `initialize` answer only when its tuples are offered tuples, in offer order, and its first
tuple is the tuple that the CLI selected from the probe claims. The session SHALL use that tuple. Otherwise the
command SHALL fail with `extension.agreement_mismatch`, exit 1 and publish no output. When the claims of the
operation session also differ from the probe, the command SHALL fail with `extension.claims_changed`, because the
describe answer comes before the agreement.

#### Scenario: Agreement differs from the probe claims
- **WHEN** a stand-in guest claims only the JSON tuple in the probe and in the operation session, but agrees on the
  Ion tuple first
- **THEN** the command fails with `extension.agreement_mismatch` and no output directory exists

#### Scenario: Agreement out of offer order
- **WHEN** a stand-in guest claims both compile tuples and agrees on the JSON tuple before the Ion tuple
- **THEN** the command fails with `extension.agreement_mismatch` and no output directory exists

#### Scenario: Claims and agreement both differ
- **WHEN** a stand-in guest reports a different version in the operation session and agrees on a tuple other than
  the selected tuple
- **THEN** the command fails with `extension.claims_changed`

### Requirement: Generate target from claims
When `--target` is absent, `generate` SHALL use the guest's only claimed backend target. When the guest claims
several targets, `--target` SHALL be required. A target that the guest does not claim SHALL be refused with
`extension.capability_unavailable` before the operation session.

#### Scenario: One claimed target
- **WHEN** a user runs `generate` with no `--target` and the guest claims only target `gleam`
- **THEN** the request has `target: "gleam"`

#### Scenario: Unclaimed target
- **WHEN** a user gives `--target moonbit` and the guest claims only `gleam`
- **THEN** the command exits 2 with `extension.capability_unavailable`

### Requirement: Claims stay the same across sessions
The describe answer of the operation session SHALL decode to the same claims as the probe. If the claims differ,
the command SHALL fail with `extension.claims_changed`, exit 1 and publish no output.

#### Scenario: Guest changes its answer
- **WHEN** a stand-in guest reports a different version in the operation session than in the probe
- **THEN** the command fails with `extension.claims_changed` and no output directory exists

### Requirement: Report records the selection
The JSON report SHALL add a `selection` object with the language ID, the source file extensions, the model tuple
or target, and the probe outcome. Existing report fields SHALL keep their names, types and meaning.

#### Scenario: Report after a Gleam compile
- **WHEN** a Gleam compile succeeds in JSON mode
- **THEN** the report has `selection.languageId: "gleam"` and `selection.fileExtensions: [".gleam"]`, and all
  earlier report fields are present
