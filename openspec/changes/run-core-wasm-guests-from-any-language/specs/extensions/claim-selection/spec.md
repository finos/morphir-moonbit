# Spec Delta

## Purpose

Defines how the portable `core-wasm-process` route reads a guest's live claims before an operation, and how those
claims select the language, model tuple and generate target, so that the CLI holds no list of languages.

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
`generate` SHALL offer the tuple of its input envelope first, then each other tuple that the CLI can convert the
model to, in the CLI's order of preference. The CLI SHALL select the first offered tuple that the guest claims for
`morphir.backend.generateModel`. Only when the guest claims no offered tuple SHALL the command exit 2 with
`extension.tuple_unavailable` before the operation session.

#### Scenario: Envelope tuple claimed
- **WHEN** a user generates from an Ion envelope and the guest claims the Ion and the JSON generate tuples
- **THEN** the session uses the Ion tuple and the CLI sends the envelope unchanged

#### Scenario: No tuple that the CLI can send
- **WHEN** the guest claims no generate tuple that the CLI offers for the envelope
- **THEN** the command exits 2 with `extension.tuple_unavailable` and no operation session starts

### Requirement: Host conversion for generate
When the selected tuple is not the envelope's tuple, the CLI SHALL convert the model to the selected tuple before
the operation session and send the converted envelope. This SHALL NOT be an error. The converted envelope SHALL
have its own payload digest and revision, and the report SHALL record the conversion.

#### Scenario: Ion envelope with a JSON-only guest
- **WHEN** a user generates from an Ion envelope whose model Morphir JSON can hold, and the guest claims only
  `morphir-ir` with `morphir-json` for generate
- **THEN** the CLI converts the model to the JSON tuple, the generate runs, and the report records the envelope
  tuple, the sent tuple and the digest of the converted payload

### Requirement: Conversion follows the loss rules
The conversion for `generate` SHALL follow the host's existing loss rules. A conversion that would drop data, such
as source or naming provenance, SHALL fail with `data.lossy_conversion`, exit 2, before the operation session. The
CLI SHALL NOT send a model that lost data.

#### Scenario: Conversion that would lose data
- **WHEN** a user generates from an Ion envelope with source provenance that Morphir JSON cannot hold, and the guest
  claims only the JSON generate tuple
- **THEN** the command exits 2 with `data.lossy_conversion` and no operation session starts

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
