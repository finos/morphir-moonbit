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

### Requirement: Model tuple must be claimed
The selected model tuple SHALL be one that the guest claims for the operation. If it is not, the command SHALL
exit 2 with `extension.tuple_unavailable` before the operation session, and the message SHALL name the tuples
that the guest claims. The default tuple and the `--model-format` choices SHALL NOT change, and the CLI SHALL
NOT fall back to another tuple.

#### Scenario: Ion default with a JSON-only guest
- **WHEN** a user compiles with no `--model-format` and the guest claims only `morphir-ir` with `morphir-json`
- **THEN** the command exits 2 with `extension.tuple_unavailable` and the message names `--model-format json`

#### Scenario: JSON selected
- **WHEN** the same user adds `--model-format json`
- **THEN** the operation session offers the `morphir-ir` and `morphir-json` tuple and the compile runs

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
