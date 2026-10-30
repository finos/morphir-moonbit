# Spec Delta

## Purpose

Defines how the MoonBit CLI runs a WASM extension guest as a worker: which guest ABIs it accepts, what authority a
guest gets, its resource bounds, and where the guest runs on native, Node and browser hosts.

## ADDED Requirements

### Requirement: Closed ABI classification
Before instantiation, the host SHALL read the module's imports and exports and classify it as exactly one known
ABI: `extism-kernel-v1` or `morphir-bytes-v1`. A module that matches neither, or both, SHALL be refused with
`extension.abi_unsupported`, naming the first import or export that does not fit.

#### Scenario: Python extension
- **WHEN** the host reads the Python extension `0.4.1` or `0.4.2` module
- **THEN** it classifies it as `extism-kernel-v1` from its `extism:host/env` imports and its `handle` and
  `morphir_extension_info` exports

#### Scenario: Module that imports WASI
- **WHEN** a module imports `wasi_snapshot_preview1.fd_write`
- **THEN** the host refuses it with `extension.abi_unsupported` and does not instantiate it

### Requirement: Declared ABI must agree
When a worker specification or release descriptor declares an ABI, the host SHALL require the classified ABI to be
the same. A declaration SHALL NOT widen what the module may import.

#### Scenario: Wrong declaration
- **WHEN** a specification declares `morphir-bytes-v1` for an Extism module
- **THEN** the host refuses with `extension.abi_mismatch`

### Requirement: No ambient authority
A WASM guest SHALL receive only the imports of its ABI. It SHALL have no file system, network, clock, environment,
process or random-number access, and the host SHALL NOT supply Extism variables, configuration, HTTP or WASI.

#### Scenario: Guest asks for HTTP
- **WHEN** an Extism module imports `extism:host/env.http_request`
- **THEN** the host refuses it with `extension.abi_unsupported`

### Requirement: Extism kernel adapter
For `extism-kernel-v1` the host SHALL keep one instance per session, call `handle` once per request with the request
bytes as input, and read the response from the output. It SHALL deliver no notification to the guest; `exit` SHALL
end the instance. A call that sets an error or traps SHALL fail the session.

#### Scenario: Python compile
- **WHEN** the host runs `initialize`, `morphir.frontend.compile` and `shutdown` on the Python guest
- **THEN** each request is one `handle` call on the same instance, and `initialized` and `exit` are not delivered

#### Scenario: Guest traps
- **WHEN** the guest traps during `handle`
- **THEN** the session fails with `extension.guest_trap` and the instance is discarded

### Requirement: Byte callback adapter
For `morphir-bytes-v1` the host SHALL provide exactly `input_len`, `input_byte` and `output_byte` and interpret the
`handle` result as today: a positive value is a response length, 0 is exit, -2 is a notification and -1 is a
failure. Requests and responses SHALL be valid UTF-8.

#### Scenario: MoonBit portable guest
- **WHEN** the host runs the MoonBit portable guest's `model.wasm`
- **THEN** compile and generate return the same envelopes as the native MoonBit guest

### Requirement: Memory ceiling
The host SHALL cap each guest's linear memory at 256 MiB, including a module that declares no maximum or a larger
one. A growth beyond the ceiling SHALL fail the call; it SHALL NOT be granted.

#### Scenario: Module without a maximum
- **WHEN** the Python module, which declares no memory maximum, tries to grow past 256 MiB
- **THEN** the call fails with `extension.memory_limit` and the session fails

### Requirement: Per-call budget
Each guest call SHALL have a deadline of 30 seconds for `extism-kernel-v1` and 10 seconds for `morphir-bytes-v1`,
inside the session deadline. Where the engine meters instructions, the host SHALL also apply a budget of
1,000,000,000 per call. The report SHALL state which bounds the host enforced.

#### Scenario: Runaway guest
- **WHEN** a guest loops forever inside `handle`
- **THEN** the call is stopped at its deadline, the outcome is deadline and the worker is gone

#### Scenario: Host without metering
- **WHEN** the guest runs on a host whose engine has no instruction metering
- **THEN** the report lists the deadline and memory ceiling as enforced and the instruction budget as not enforced

### Requirement: Native WASM worker runtime
The native CLI SHALL run WASM guests in a separate process started from its own verified executable in a documented
worker mode, under the process worker rules. The native CLI SHALL need no Node, no Extism library supplied by the
user and no Rust helper.

#### Scenario: Python from the native CLI
- **WHEN** the native CLI compiles a Python file with the Python extension
- **THEN** the guest runs in a worker process of the CLI's own executable and that process's group is gone afterwards

#### Scenario: Worker mode output
- **WHEN** the worker mode runs
- **THEN** its stdout carries only MEP frames and its startup and diagnostic reports go to stderr

### Requirement: Node worker threads
The npm CLI SHALL run WASM guests in a Node worker thread. On deadline or cancellation the host SHALL terminate the
thread and wait until it has terminated before it returns.

#### Scenario: Cancel a WASM compile in the npm CLI
- **WHEN** the user presses Ctrl+C during a Python compile in the npm CLI
- **THEN** the worker thread is terminated, the outcome is cancelled and the exit status is 130

### Requirement: Browser Web Workers
A browser host SHALL run each WASM guest in its own Web Worker, connected through a message channel that carries
whole MEP messages. On deadline or cancellation it SHALL terminate that Web Worker.

#### Scenario: MoonBit and Python guests in a browser
- **WHEN** a page runs the browser host with the MoonBit portable guest and the Python extension
- **THEN** describe, compile and generate return the same results as on Node

#### Scenario: Runaway guest in a browser
- **WHEN** a guest in a Web Worker does not answer before its deadline
- **THEN** the Web Worker is terminated and the page stays responsive

### Requirement: Unsupported WASM features
The host SHALL refuse at load, with `extension.wasm_feature_unsupported`, a module that needs a WASM feature its
engine does not support, and SHALL name the feature when the engine reports it.

#### Scenario: Engine without a feature
- **WHEN** a module needs a feature the native engine was built without
- **THEN** the load fails with `extension.wasm_feature_unsupported` before any request
