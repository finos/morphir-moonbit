# WASM workers

These packages run a Morphir extension that is a WASM module as a worker of the
CLI. The session core in `finos/morphir-host/worker` sees only a `Channel` that
carries whole MEP messages; these packages supply that channel for a module, on
the native CLI and on the npm CLI. The rules come from
`specs/extensions/wasm-workers` in the OpenSpec change
`host-extensions-as-workers`, and from its design decisions WASM-1 to WASM-4.

| Package | Targets | Holds |
| --- | --- | --- |
| `worker/wasm` | all | The import and export reader, the ABI classifier, the memory-maximum rewrite. |
| `worker/wasm/guest` | native, js | The `morphir-bytes-v1` and Extism adapters over the `moonrockz/extism` engine, and the worker report. |
| `worker/wasm/native` | native | The `morphir extension worker` mode and the native WASM launcher. |
| `worker/thread` | js | The Node worker-thread launcher. |
| `worker/thread/entry` | js | The entry module of a worker thread, shipped as `dist/wasm-worker.js`. |
| `worker/wasm/fixtures` | all | Crafted modules for the tests. |

The design puts all of the WASM code in one package. It is split because the
engine of `moonrockz/extism` builds only on native and js, while the reader and
the classifier build on all four targets.

## A guest from start to stop

Assume that the native CLI must run the Python extension `0.4.2`, a module of
4.7 MB that imports eight Extism kernel functions.

1. `WasmModule::read` reads the type, import, function, memory and export
   sections. `classify` finds imports from `extism:host/env`, so the profile is
   `extism-kernel-v1`. Every import must be in that profile's import surface,
   with the surface's type, and the module must export `handle` as
   `() -> i32`. An import outside the surface, such as `env.open_socket`, is
   refused with `extension.abi_unsupported` and its name. A declared ABI that
   differs is refused with `extension.abi_mismatch`.
2. `with_memory_ceiling` sets the memory maximum to 256 MiB, because the module
   declares none. A shared, 64-bit or second memory is refused with
   `extension.wasm_feature_unsupported`. The engine's pure feature scan refuses
   any other feature that the engine does not have, by its name.
3. The native launcher reads the CLI's own executable (through `/proc/self/exe`
   on Linux; on macOS and Windows the real path must be a regular file), hashes
   the bytes it read, and writes a private copy with the module beside it. It
   starts the copy as a process worker:
   `morphir extension worker --abi extism-kernel-v1 --module <path>
   --build-identity <hex> --request-bytes <n> --response-bytes <n> --json`.
4. The worker checks the build identity, loads the module with the Extism
   adapter, reports `started` on stderr, and answers each Content-Length frame
   on stdin with a frame on stdout, until `exit`.
5. When stdout ends early, the launcher's channel reads the last `fault` or
   `refused` event of the report and raises `GuestFailed` or `Refused`, so the
   session ends with the guest's own code.

Steps 1 and 2 run before any process or thread starts, so a refusal costs
nothing.

## Profiles and adapters

`morphir-bytes-v1` imports exactly `morphir_bytes_v1.input_len`,
`input_byte` and `output_byte`. The result of `handle` is the length of the
response when it is positive, exit when it is 0, a notification when it is -2
and a failure when it is -1. Requests and responses must be valid UTF-8.

`extism-kernel-v1` may import the Extism kernel and host functions
(`extism:host/env`), the four Morphir host functions (`extism:host/user`) and
any WASI preview 1 function with its witx type. The adapter keeps one plugin
instance for the session and calls `handle` once per request. It delivers no
notification, and `exit` ends the instance. The host functions follow WASM-4:

| Imports | Policy |
| --- | --- |
| `config_get` | No configuration. |
| `var_get`, `var_set` | A store of at most 1 MiB that lives only for the session. |
| `log_*`, `morphir_log` | Guest output, in the report. |
| `http_request` | Refused: the call fails and the report records the method and URL. |
| `morphir_get_workspace_info` | `{"root": <private working directory>, "output_dir": ""}`. |
| `morphir_cache_ir`, `morphir_get_cached_ir` | A cache of at most 16 MiB that lives only for the session. |
| WASI preview 1 | No preopens, arguments, environment or stdin; clocks and random bytes; stdout and stderr as guest output; other calls return an error code. |

## Bounds

| Bound | Native worker mode | Node worker thread |
| --- | --- | --- |
| Memory ceiling, 256 MiB | Enforced by the engine | Enforced: the rewritten maximum |
| Instruction budget, 1,000,000,000 per call | Enforced by WAMR metering | Not enforced: the js engine has no metering |
| Call deadline, 30 s Extism and 10 s bytes | Enforced: the engine interrupts the call | Enforced: the channel terminates the thread |
| Session deadline and cancellation | The process group is stopped | The thread is terminated, and the host waits until it has terminated |

`Channel::bounds` states these bounds, and the session report keeps them. An
exhausted budget fails the session with `extension.budget_exhausted`, a passed
call deadline ends it as a deadline, a refused memory growth fails it with
`extension.memory_limit`, and a trap with `extension.guest_trap`.

## The worker mode

`morphir extension worker` is an internal subcommand of the native CLI. The
native entry runs it before it prepares the CLI host, so nothing but MEP frames
reaches stdout.

- stdout carries only Content-Length framed MEP messages.
- stderr carries the report. With `--json`, each event is one line:

```json
{"profile":"morphir/command-event","contractVersion":"0.1.0","command":"extension worker","sequence":3,"event":"fault","fault":{"kind":"trap","message":"Unreachable"}}
```

| Event | Members |
| --- | --- |
| `started` | `abi`, `moduleSha256`, `buildIdentity`, `bounds` |
| `output` | `output`: a guest output as text |
| `fault` | `fault.kind`: `trap`, `memory-limit`, `call-deadline`, `budget-exhausted` or `failure`; `fault.message` |
| `refused` | `error.code`: an `extension.*` refusal code; `error.message` |
| `exited` | `exitCode` |

Without `--json` the same events are text lines. `--help` writes the help to
stdout and serves nothing; `--help --json` writes a `morphir/command-result`
with `result.help`.

| Exit status | Meaning |
| --- | --- |
| 0 | The guest served until `exit`. |
| 1 | A guest fault, an invalid frame, or stdin ended before `exit`. |
| 2 | Invalid arguments. |
| 3 | A refusal before any request: another build identity, an ABI or a WASM feature. |

The build identity is a SHA-256 over the worker contract version
(`morphir-wasm-worker/0.1.0`), the host version, the SHA-256 of the Extism
kernel and the engine's features. A worker of another identity refuses with
`extension.worker_runtime_mismatch`. The CLI has no build stamp, so two
development builds of the same version, kernel and engine features share an
identity. Within one CLI process, the launcher also refuses an executable whose
bytes changed since its first launch.

## The Node worker thread

The npm CLI runs each guest in a Node worker thread from
`dist/wasm-worker.js`, the entry module that `worker/thread/entry` builds.
`ThreadLauncher::bundled` finds it beside the CLI bundle. The thread has an
empty environment and writes nothing to stdout; it posts responses and the same
report events through its port.

## Dependency on moonrockz/extism

`moonrockz/extism` is not on Mooncakes yet. `moon.work` names a read-only clone
of its branch `DamianReeves/extism-host` at commit
`9d95db0` in the ignored `.dev/extism` directory:

```bash
git clone --branch DamianReeves/extism-host https://github.com/moonrockz/extism.git .dev/extism
git -C .dev/extism checkout 9d95db0
```

The pull request that adds these packages switches to the published version
in its last commit.

## Tests with real guests and executables

The package tests run crafted modules on every target. Tests with real guests
and built executables run when these variables name them, and return early
otherwise:

| Variable | Names |
| --- | --- |
| `MORPHIR_PORTABLE_GUEST` | `model.wasm` of the portable MoonBit guest (`mise run package:mep-extension`) |
| `MORPHIR_NATIVE_GUEST` | The native MoonBit guest (`moon build --target native --release` in `apps/morphir-extension`) |
| `MORPHIR_PYTHON_EXTENSIONS` | A directory with `0.4.1/` and `0.4.2/` release assets of the Python extension |
| `MORPHIR_CLI` | A native CLI build (`moon build --target native --release` in `apps/morphir`) |
| `MORPHIR_WASM_THREAD_ENTRY` | The built entry module (`moon build --target js --release pkgs/morphir-host/worker/thread/entry`) |

```bash
moon test -p finos/morphir-host/worker/wasm/guest --target native
moon test -p finos/morphir-host/worker/wasm/native --target native
moon test -p finos/morphir-host/worker/thread --target js
```
