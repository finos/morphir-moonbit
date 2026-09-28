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
