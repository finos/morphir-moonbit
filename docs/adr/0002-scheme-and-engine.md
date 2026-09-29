# Separate Scheme execution from project orchestration

Morphir Scheme supplies a reader, lexical evaluator, IR frontend/backend and typed
transformation procedures. Morphir Engine owns source discovery, manifests,
configuration precedence, stage diagnostics and artifacts. Both use the current
IR API; versioned JSON input goes through the existing codecs and migrations.

The specialized language takes inspiration from bobzhang's MoonBit Scheme R6RS
implementation, but has an independent, smaller implementation and no dependency
on its runtime. It supports transform scripts and a functional frontend subset;
full R6RS conformance and type inference are outside this foundation.

Filesystem and network capabilities belong to explicit host adapters. A synchronous
host contract and an immutable memory host keep the engine available on all four
MoonBit targets. Async applications can prepare source snapshots before running
transformations. Output artifacts are returned, leaving persistence to the host.

Workspace and project scripts can select frontends/backends and supply typed IR
transforms. Each project has an isolated Scheme session; files share its script
state in sorted order. Each input currently produces an independent artifact.
Cross-file linking, dependency resolution and CLI filesystem commands need host
and compiler integration beyond this engine contract.

Tail calls use a trampoline with arena-backed lexical environments. This avoids
closure/environment reference cycles on reference-counted targets, but retains
frames for the session lifetime. Explicit frame limits and short-lived job sessions
bound that retention; environment reclamation remains future work.


## Workspace host integration

The approved workspace design extends this boundary with a host runner. Configuration
and workspace discovery consume portable snapshots. The engine resolves scripts and
source selection into a plan before the host materializes selected source contents.
Execution returns artifacts; publication remains a host capability.

TOML configuration follows upstream Morphir workspace layouts and merge rules.
Shared workspace/global layers exclude project identity and workspace roots when
applied to members. Discovery exposes the protocol-v1 request/snapshot shapes for the
implemented TOML subset. YAML decoding remains unsupported with explicit diagnostics.

Native and Node adapters provide filesystem execution. WASM uses Preview 1 imports
and a preopened development root; WASM-GC uses an explicit embedding interface.
Async hosts prepare snapshots and publish results around the synchronous core.

The filesystem publisher stages all outputs, serializes writers with an exclusive
lock, and replaces task destinations with backups for recovery. This is not an atomic
workspace transaction. Failures report committed destinations; failed rollback keeps
backups for explicit recovery. Scheme cancellation checks run within evaluation.
