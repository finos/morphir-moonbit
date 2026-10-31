# Spec Delta

## Purpose

Defines how the portable `core-wasm-process` route pins, checks and runs a core-Wasm guest that was not assembled
by MoonBit, through its release descriptor and the execution profile instead of the MoonBit artifact manifest.

## ADDED Requirements

### Requirement: Two artifact forms
A `core-wasm-process` pin SHALL name its artifact in one of two forms. The assembly form SHALL keep its fields:
`directory`, `wasmSha256` and `manifestSha256`. The module form SHALL have `form: "module"`, `directory`,
`descriptor` (a file name), `descriptorSha256`, `moduleSha256`, `extensionId` and `version`. Other fields SHALL be
refused with `extension.invalid_pin`.

#### Scenario: Existing assembly pin
- **WHEN** a user runs a pin written for the MoonBit guest before this change
- **THEN** the CLI accepts it and the run is the same as before

#### Scenario: Module pin with a manifest digest
- **WHEN** a module form pin also has `manifestSha256`
- **THEN** the command exits 2 with `extension.invalid_pin` and names the field

### Requirement: Descriptor integrity
The CLI SHALL read the descriptor through a bounded read of at most 1 MiB and SHALL require its SHA-256 to equal
`descriptorSha256` before it decodes it. A mismatch SHALL exit 2 with `extension.identity_mismatch`, and no guest
SHALL start.

#### Scenario: Changed descriptor
- **WHEN** one byte of `morphir-gleam-0.4.0.release.json` changes after the pin was written
- **THEN** the command exits 2 with `extension.identity_mismatch` and no guest starts

### Requirement: Descriptor content
The descriptor SHALL have `schemaVersion` `2.0.0-draft.2`, and its `extensionId` and `version` SHALL equal the
pin. Exactly one artifact SHALL have `runtime: "core-wasm"` and `sha256` equal to `moduleSha256`, and a `filename`
with no path separator. Its `executionProfile` SHALL equal the pin's and the host's. Otherwise the command SHALL
exit 2 with `extension.invalid_descriptor`.

#### Scenario: Gleam 0.4.0 descriptor
- **WHEN** the pin names the `morphir-gleam` 0.4.0 bundle with its descriptor and module digests
- **THEN** the CLI selects the artifact `morphir-gleam-0.4.0.wasm` and accepts the descriptor

#### Scenario: Wrong execution profile
- **WHEN** the descriptor artifact names an execution profile digest other than the host's
- **THEN** the command exits 2 with `extension.invalid_descriptor` and no guest starts

### Requirement: Critical members
Every name in the selected artifact's `critical` list SHALL be a member that the host understands and checks. The
host SHALL understand `runtime` and `executionProfile`. An unknown critical name SHALL be refused with
`extension.invalid_descriptor`, and the message SHALL name it.

#### Scenario: Unknown critical member
- **WHEN** the artifact has `critical: ["runtime", "executionProfile", "memory64"]`
- **THEN** the command exits 2 with `extension.invalid_descriptor` and names `memory64`

### Requirement: Verified staging
The host helper SHALL read the descriptor and the module through no-follow descriptors, check each SHA-256 against
the pin and run the guest only from the copies it checked. The module SHALL be at most 128 MiB. A module file name
that leaves the directory, or a path through a symbolic link, SHALL be refused with `extension.unsafe_artifact`.

#### Scenario: Module replaced after the check
- **WHEN** the module file in the pinned directory is replaced while the guest runs
- **THEN** the guest runs the checked copy and the run is not changed

#### Scenario: Module digest mismatch
- **WHEN** the module bytes do not match `moduleSha256`
- **THEN** the command exits 2 with `extension.identity_mismatch` and no guest starts

### Requirement: Execution profile structure
Before it instantiates a module form guest, the Node host SHALL check the module itself against
`morphir/mep-bytes-v1/v1-draft`: imports only from `morphir_bytes_v1.input_len: () -> i32`,
`input_byte: (i32) -> i32` and `output_byte: (i32) -> ()`, an exported function `handle: () -> i32`, and exactly
one defined, unshared 32-bit memory with a maximum of at most 4,096 pages. Any other import, signature or memory
SHALL be refused.

#### Scenario: Gleam module
- **WHEN** the host checks `morphir-gleam-0.4.0.wasm`
- **THEN** the check passes and the guest is instantiated

#### Scenario: Extra import
- **WHEN** a crafted module also imports `wasi_snapshot_preview1.fd_write`
- **THEN** the run fails with an incompatible-module error that names that import, and the guest is not
  instantiated

#### Scenario: Wrong signature
- **WHEN** a crafted module imports `morphir_bytes_v1.output_byte` with the type `(i64) -> ()`
- **THEN** the run fails before instantiation and names `morphir_bytes_v1.output_byte`

### Requirement: Descriptor claims equal live claims
For a module form artifact, the claims in the selected descriptor artifact SHALL decode to the same claims as the
live describe answer, and the live extension ID and version SHALL equal the pin. A difference SHALL exit 2 with
`extension.claims_mismatch`, and no operation session SHALL start.

#### Scenario: Descriptor claims a different language
- **WHEN** a descriptor, written again with a correct digest, claims language `elm` but the guest claims `gleam`
- **THEN** the command exits 2 with `extension.claims_mismatch`

### Requirement: Claims are not authority
Descriptor and live claims SHALL select requests and SHALL be compared. They SHALL NOT widen the imports, memory,
time or file access of a guest. The report SHALL show the descriptor `gitCommit` as a claim, not as verified
origin.

#### Scenario: Report origin
- **WHEN** a module form compile succeeds in JSON mode
- **THEN** the report shows the descriptor digest, the module digest and `gitCommit` under `pin.artifact`, with
  `origin: "claimed"`

### Requirement: Same session behavior for both forms
After the checks, a module form guest SHALL run with the same session order, limits, deadline, cancellation,
output publication, report schema and exit status as an assembly form guest.

#### Scenario: Deadline with a module form guest
- **WHEN** a module form compile passes `--timeout`
- **THEN** the command exits 124, the guest process group is stopped and no output directory exists
