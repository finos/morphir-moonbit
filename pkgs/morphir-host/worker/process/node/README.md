# Node process workers

`finos/morphir-host/worker/process/node` runs process workers for the npm CLI
through Node's `child_process` (design decision PROC-2). It builds only for the
js target. The native CLI uses `worker/process/native`. Both launchers share the
framing, the stderr tail, the stop bounds and the staging rules of
`worker/process`, and both pass the same
[conformance suite](../conformance/README.md).

## Example

```moonbit
let spec = @worker.WorkerSpec::new(artifact, Process(platform~, args~))
let channel = @node.NodeProcessLauncher::new().launch(spec, limits)
channel.send(request)
let response = channel.receive()
channel.send(exit)
let stop = channel.close()
```

`launch` refuses a WASM runtime and an artifact in memory with
`RuntimeUnavailable`, and a platform other than the host's with
`PlatformMismatch`. Then it stages the artifact and starts the verified copy.
The channel checks frames against the session's `limits`.

## How a worker starts

1. Staging opens the artifact with `O_NOFOLLOW` and `O_NONBLOCK`, checks with
   `fstat` that it is a regular file of at most 512 MiB, and reads it through
   the same descriptor. A link gives `ArtifactUnreadable(SymbolicLink)`, a
   directory or FIFO `NotRegularFile`.
2. `VerifiedArtifact::check` hashes the bytes that were read and compares them
   with the specification. A mismatch gives `DigestMismatch`, and no process
   starts.
3. Staging writes the bytes to a new private directory (mode 0700), as a file
   that only its owner can read and execute (mode 0500), with an empty `work`
   directory next to it. The worker runs that copy, so a later change to the
   original path does not change what runs.
4. `spawn` starts the copy with `detached: true` (a new process group on Unix),
   three pipes, `windowsHide: true`, `work` as its working directory and the
   argument array unchanged.

The worker's environment is empty on Linux and macOS. On Windows it holds only
`SystemRoot`, which Windows programs need to load system libraries. macOS adds
`__CF_USER_TEXT_ENCODING` to every process that has none; the host does not
pass it.

## Channel

- `send` encodes one frame with `FrameWriter` and writes it to stdin with a
  promise-based write through `@js_async.run_promise`. A frame above the
  session's request limit (4 MiB by default) gives
  `FrameLimit(direction=Request)`, and nothing is written.
- `receive` reads stdout through `@js_async.ReadableStream` (`Readable.toWeb`)
  and decodes frames with `FrameReader`. The reader refuses a declared size
  above the session's response limit (16 MiB by default) with
  `FrameLimit(direction=Response)` before it reads the body. Text that is not
  a frame gives `FrameInvalid`.
- Node drains stderr while the worker runs into a `StderrBuffer`, which keeps the
  last 64 KiB. The stop carries the tail and marks it truncated when bytes were
  dropped.
- A cancelled `send` or `receive` passes the cancellation through unchanged.

## Stop

`close` ends stdin and waits at most 2 seconds for the worker to exit. An
`abort` during that wait ends it at once. `abort` stops the tree at once. Both
run their cleanup under `protect_from_cancel` and return the first stop on
every later call.

| Host | Tree | Stop | Confirmation | Method |
| --- | --- | --- | --- | --- |
| Linux, macOS | process group (`detached: true`) | `process.kill(-pid, 'SIGKILL')` | the `exit` event, then `process.kill(-pid, 0)` until `ESRCH` | `GroupSignal` |
| Windows | the root's process tree | `taskkill /PID pid /T /F` | the root's `exit` event | `TreeTermination` |

A worker that exits by itself reports `ExitedAfterExit`. On Unix, if its group
still has a member after the exit, the host signals the group and reports
`GroupSignal` with the exit status. Each confirmation step has a 5 second bound
(`STOP_CONFIRM_MS`). When the host cannot confirm the stop, the status is
`Unconfirmed(reason)`, the host keeps the private directory, and it releases
the worker's pipes and handle so that the CLI can still exit. Otherwise it
removes the private directory before it returns.

## Differences from the native launcher

- **Windows tree termination.** Node cannot create a job object without the
  PowerShell and C# bridge that this change retires. The npm CLI on Windows
  stops a worker with `taskkill /T /F` from its root and reports
  `TreeTermination`, not `JobTermination`. `taskkill /T` follows parent process
  IDs, so it reaches descendants only while the root runs. A descendant that
  outlives a worker which exited by itself is not stopped. The conformance case
  "descendants stop after the worker exits" applies only to `Group` and `Job`
  ownership for this reason.
- **Host exit.** On Windows the native CLI's job object kills the worker when the
  CLI dies. The npm CLI has no job: when it dies, the worker's stdin closes, and
  a conformant worker exits at the end of its input.
- **Links on Windows.** Windows has no `O_NOFOLLOW`. There the host refuses a
  link that `lstat` reports before it opens the artifact, so a link that is
  created between the two calls is not detected.
- **Signals.** The Node launcher sends SIGKILL to the group at once. It does not
  send SIGTERM first.

## Tests

`moon test --target js -p finos/morphir-host/worker/process/node` runs the
conformance suite against the Node fixture worker
(`fixtures/worker.mjs`), the staging tests and the stop decision tests. The
tests need Node to run the fixture worker; the launcher itself does not need a
Node executable from the user. On Linux and macOS the staging tests use a small
`/bin/sh` wrapper as the artifact. On Windows, where Node cannot start a script
without a shell, the artifact is the Node executable. The same test file covers
the Windows `taskkill` path when it runs on Windows.
