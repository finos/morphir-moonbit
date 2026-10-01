# Morphir hosts

`finos/morphir-host` supplies input, configuration, cancellation and publication capabilities around the portable Morphir engine. The engine has no dependency on this module.

## Embedding

Construct a `Mount` with `kind`, `read` and shallow `list` callbacks. Paths are relative to the mount. Entry kinds are 0 missing, 1 regular file, 2 directory, 3 symlink and 4 unsupported special file. Directory listings contain immediate child names.

`Host::new` accepts a mount, optional publisher, explicit environment, system/global configuration documents, cancellation callback, event callback and resource limits. `Mount::memory` copies its input map. `Publisher::memory` commits artifacts to a supplied output map.

Hosts can also supply an optional `toolchain` provider and use
`Host::toolchain_request` to compile or execute through its explicit capabilities.
See [acquired tooling](toolchain/README.md) and [embedded tooling](embedding/README.md)
for process and in-memory providers. Tooling calls emit a host phase event and
check cancellation before and after the provider call; providers enforce their
own operation limits and lifecycle. No tooling is acquired implicitly.

The invocation sequence is:

1. `Host::snapshot()` captures directory inventory, manifests and Scheme configuration.
2. `workspace.discover(snapshot.tree, ...)` resolves configuration and member metadata.
3. `Engine::plan(snapshot.engine_host(), workspace, request, cancelled=host.cancelled)` validates selection and scripts and freezes source paths and destinations.
4. `Host::run(engine, plan)` snapshots selected contents, runs the pipeline, stages artifacts and publishes each task destination.

Hosts can prepare snapshots and consume returned artifacts asynchronously in their own environment. Core execution is synchronous. Long-running Scheme evaluation checks cancellation at each evaluator step; asynchronous applications must arrange a callback whose state can change while their runner executes. Frontend/backend callbacks must provide their own internal cancellation if needed.

Hosts that provide native runtime behavior pass `bind_runtime` when planning. The
engine calls it once per project session before evaluating configuration scripts.
This keeps host capabilities explicit and available to `ir-eval` in those scripts.

The existing `morphir-engine.Host` and `Engine::run` APIs remain available for callers that only need artifacts. No filesystem, process or network access is implicitly available to Scheme.

### Typed content and bytes

`Host::run_content(engine, plan, publisher, read_bytes=Some(reader))` snapshots
text or raw bytes according to the plan and returns `ContentResult`. Its artifacts
carry `data.Content::Text` or `Binary`, plus their selected format. Supply
`ContentPublisher::memory` for typed in-memory outputs or
`ContentPublisher::filesystem` for files. `Mount::filesystem_bytes(root)` supplies
a confined raw-byte reader alongside the existing text mount.

`ContentPublisher.write_bytes` advertises binary support. Missing byte readers
or publishers fail capability checks before source reads or staging. The
`ContentPublisher::text` adapter retains existing publisher callbacks and rejects
binary output. `Host::run` uses that adapter, so existing text callers and readable
Ion checkpoints share the typed execution and publication lifecycle. Byte
snapshots remain bytes throughout execution and staging.

## Runtime adapters

| Target | Adapter |
| --- | --- |
| Native | OS arguments/environment, filesystem and stderr/exit |
| JavaScript | Node filesystem adapter; memory embedding does not require filesystem access |
| WASM | WASI Preview 1; the development root is preopened directory fd 3 |
| WASM-GC | `morphir_host_v1` imports supplied by the embedding application |

Run WASM artifacts with `node pkgs/morphir-host/runners/wasm.mjs <artifact.wasm> [arguments]`. The runner preopens the current directory for WASI. Other WASI runners can supply equivalent arguments, environment and preopens. There are no Moonrun-specific imports in the WASI CLI.

WASM-GC exchanges JSON responses through opaque UTF-16 string handles. Imports are `begin`, `append`, `length`, `at` and `request`; `request` takes operation and two string arguments and returns `{value: ...}` or `{error: ...}`. The supplied runner implements filesystem operations, arguments, environment, platform identity, stderr and exit. Console output uses `spectest.print_char`. These imports are an explicit embedding contract, not WASI.

Optional WASM-GC operations `bytes_supported`, `read_bytes` and `write_bytes`
extend this interface. `bytes_supported` returns true when both byte operations
are implemented; missing operations mean unsupported. `read_bytes(path)` returns
a JSON array of integers 0 through 255. `write_bytes(path, payload)` receives that
array encoded as JSON in the second argument. The supplied runner implements
them. Older embedding hosts continue to support text pipelines without adding
imports. These JSON arrays are a byte transport for the embedding ABI, independent
of the engine's selected data codec.

Desktop hosts resolve system/global configuration using the platform config directory and Morphir home rules. WASI only accesses its preopen. Its CLI accepts optional `.morphir-host/system/morphir.{toml,yaml}` and `.morphir-host/user/morphir.{toml,yaml}` within that preopen. Library callers can supply separate read-only configuration documents directly.

## Publication and limits

`Publisher.guarantee` declares atomic task publication, recoverable task replacement or host-managed semantics. Events distinguish phases, diagnostics and committed destinations.

Configuration or transformation failures publish nothing. Successful transformations are staged before any destination is replaced. A task owns its `compile.dest` directory, including removal of its stale artifacts on the next successful publication.

Filesystem publishers acquire `.morphir-publish.lock` under the output root with exclusive directory creation. They move an existing task directory to a backup, then move its staged replacement into place. This provides recoverable task replacement, with a brief interval when the destination is absent. It does not provide atomic replacement across tasks. Reports list the destinations that actually committed.

Normal completion/failure removes only the invocation's staging and backup data. If restoring a backup fails, the publisher preserves the lock and backup and reports their location. A lock left by a crashed process requires inspection and explicit recovery; another invocation never removes it automatically.

Default limits are 10,000 entries, depth 64 and 64 MiB per configuration/source/artifact phase. Filesystem adapters limit each text or byte read to 16 MiB. Source contents are snapshots, not a streaming interface. Files changing during snapshot preparation can yield contents from different moments. Checkpoint codecs enforce their own byte/traversal budgets in addition to host limits.

Filesystem mounts reject symlinks and special files and check path components before each operation. They assume the granted filesystem is not being maliciously changed concurrently. These adapters are not OS sandboxes. WASI preopens provide an additional runtime confinement boundary. Memory and remote adapters can materialize confined symlinks before supplying a snapshot.

Generated libraries with `Required(target)` pass through a `LibraryBuildProvider`.
A provider declares the library contracts it can build and acquires a fresh lease
with `build` and `dispose` callbacks. Embedded package compilation does not imply
this capability. The host hashes the exact source/member snapshot with SHA-256,
checks the fresh lease and project/target/dependency evidence, and emits a binary
Ion `morphir-library-build-v1` receipt. All required builds and lease disposal must
succeed before publication begins. Cancellation is checked before and after
provider calls. Providers must bound their own running processes and deadlines.

The explicit process adapter invokes a supplied Node helper, compiler/core home
and supplied dependency directories. It creates a host-owned temporary lease;
the helper materializes a private workspace, verifies pinned compiler/core and
SDK identities, builds with `--frozen`, and verifies source identities again.
Dependency source trees exclude `_build`, `.mooncakes`, `.git` and `node_modules`.
Core identities include bundled compiler inputs and confined file symlinks.
This identity profile records content, not timestamps. Supply an installation
whose matching core is already bundled; a build that changes its inputs fails.
The helper uses no installation, update, registry acquisition or fallback build.
Cleanup covers the entire lease, including workspaces left by failed processes.
