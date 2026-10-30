///|
extern "C" fn executable_path_ffi() -> Bytes = "morphir_wasm_worker_executable_path"

///|
/// The path of the running executable: `/proc/self/exe` on Linux, the real
/// path of the executable on macOS and Windows.
fn executable_path() -> String raise @worker.LaunchError {
  let bytes = executable_path_ffi()
  guard bytes.length() > 0 else {
    raise LaunchFailed("the path of the CLI executable is not known")
  }
  @utf8.decode(bytes) catch {
    _ => raise LaunchFailed("the path of the CLI executable is not UTF-8")
  }
}

///|
/// Where the WASM launcher finds the executable that has the worker mode.
pub(all) enum WorkerExecutable {
  /// The running CLI itself.
  Own
  /// Another executable with the same worker mode, for tests.
  At(String)
}

///|
/// Starts WASM workers on native (WASM-2). Each worker is the CLI's own
/// executable in its worker mode, started as a process worker: the launcher
/// reads the executable, hashes the bytes it read and runs a private copy of
/// them, with the module in the same private directory. Before it starts the
/// worker, it classifies the module, checks its features and caps its
/// memory, so a refusal costs no process.
pub struct WasmProcessLauncher {
  priv process : @process.ProcessLauncher
  priv staging_root : String?
  priv executable : WorkerExecutable
  priv identity : BuildIdentity
  /// The SHA-256 of the executable at its first launch. A later launch
  /// that reads other bytes is refused: the CLI was replaced while it ran.
  priv mut executable_sha256 : @worker.Sha256?
}

///|
pub fn WasmProcessLauncher::new(
  staging_root? : String,
  executable~ : WorkerExecutable = Own,
  grace_ms~ : Int32 = @shared.EXIT_GRACE_MS,
  confirm_ms~ : Int32 = @shared.STOP_CONFIRM_MS,
) -> WasmProcessLauncher {
  {
    process: @process.ProcessLauncher::new(
      staging_root?,
      grace_ms~,
      confirm_ms~,
    ),
    staging_root,
    executable,
    identity: BuildIdentity::current(),
    executable_sha256: None,
  }
}

///|
/// The bytes of the module that a specification names, checked against its
/// SHA-256.
async fn module_bytes(artifact : @worker.ArtifactRef) -> Bytes {
  let bytes = match artifact.source {
    Memory(bytes) => bytes
    File(path) =>
      @fs.read_file(path.to_string()).binary() catch {
        error =>
          raise @worker.LaunchError::ArtifactUnreadable(
            Unreadable(detail=Some(@debug.to_string(error))),
          )
      }
  }
  @shared.VerifiedArtifact::check(bytes, artifact).bytes()
}

///|
/// Reads the executable with the worker mode. On macOS and Windows the path
/// must name a regular file.
async fn WasmProcessLauncher::read_executable(
  self : WasmProcessLauncher,
) -> (String, Bytes) {
  let path = match self.executable {
    Own => executable_path()
    At(path) => path
  }
  if !path.has_prefix("/proc/") {
    let kind = @fs.kind(path, follow_symlink=false) catch {
      _ => raise @worker.LaunchError::ArtifactUnreadable(NotRegularFile)
    }
    guard kind is Regular else {
      raise @worker.LaunchError::ArtifactUnreadable(NotRegularFile)
    }
  }
  let bytes = @fs.read_file(path).binary() catch {
    error =>
      raise @worker.LaunchError::ArtifactUnreadable(
        Unreadable(detail=Some(@debug.to_string(error))),
      )
  }
  (path, bytes)
}

///|
#cfg(platform="windows")
let path_style : @worker.PathStyle = Windows

///|
#cfg(not(platform="windows"))
let path_style : @worker.PathStyle = Posix

///|
#cfg(platform="windows")
let separator : String = "\\"

///|
#cfg(not(platform="windows"))
let separator : String = "/"

///|
/// Writes a private copy of the executable and the module: `bin/<name>`,
/// `bin/module.wasm` and an empty `work` directory, usable only by the
/// host's user.
async fn WasmProcessLauncher::stage(
  self : WasmProcessLauncher,
  path : String,
  executable : Bytes,
  module_ : Bytes,
) -> (@shared.StagedArtifact, String) {
  let digest = @worker.Sha256::of(executable)
  match self.executable_sha256 {
    None => self.executable_sha256 = Some(digest)
    Some(first) if first != digest =>
      raise @worker.LaunchError::WorkerRuntimeMismatch(
        host=self.identity.to_string(),
        worker="an executable replaced while the CLI ran (SHA-256 \{digest})",
      )
    Some(_) => ()
  }
  let reference = @worker.ArtifactRef::new(
    File(
      @worker.ArtifactPath::parse(path, path_style) catch {
        _ => raise @worker.LaunchError::LaunchFailed("invalid executable path")
      },
    ),
    digest,
  )
  let verified = @shared.VerifiedArtifact::check(executable, reference)
  let directory = @async.protect_from_cancel(() => {
    match self.staging_root {
      None => @fs.tmpdir(prefix="morphir-wasm-worker-")
      Some(root) => {
        let directory = root + separator + "morphir-wasm-worker-\{@async.now()}"
        @fs.mkdir(directory, permission=0o700)
        directory
      }
    }
  })
  let staged = verified.stage_in(directory~, style=path_style)
  let module_path = directory +
    separator +
    @shared.STAGED_BIN_DIRECTORY +
    separator +
    "module.wasm"
  let mut done = false
  defer (if !done {
    @async.protect_from_cancel(() => @process.unstage(staged))
  })
  @async.protect_from_cancel(() => {
    @fs.mkdir(
      directory + separator + @shared.STAGED_BIN_DIRECTORY,
      permission=0o700,
    )
    @fs.mkdir(staged.working_directory(), permission=0o700)
    @fs.write_file(
      staged.executable(),
      executable,
      create_mode=CreateNew,
      permission=0o700,
    )
    @fs.write_file(
      module_path,
      module_,
      create_mode=CreateNew,
      permission=0o600,
    )
  })
  @async.pause()
  done = true
  (staged, module_path)
}

///|
pub extend WasmProcessLauncher with @worker.Launcher::{launch}

///|
/// Checks and stages a WASM specification and starts the worker mode with
/// the session's frame limits. A refusal of the module comes before any
/// process starts.
pub impl @worker.Launcher for WasmProcessLauncher with fn launch(
  self,
  spec,
  limits,
) {
  guard spec.runtime is Wasm(abi~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Wasm])
  }
  let bytes = module_bytes(spec.artifact)
  let prepared = @wasm.PreparedModule::prepare(bytes, declared?=abi)
  if @guest.missing_feature(bytes) is Some(feature) {
    raise @worker.LaunchError::WasmFeatureUnsupported(feature=Some(feature))
  }
  let (path, executable) = self.read_executable()
  let (staged, module_path) = self.stage(path, executable, bytes)
  let options : WorkerOptions = {
    abi: prepared.abi,
    module_path,
    build_identity: self.identity,
    request_bytes: limits.request_bytes,
    response_bytes: limits.response_bytes,
    call: None,
    memory_pages: None,
    json: true,
  }
  let channel = self.process.start(
    staged,
    ["extension", "worker", ..options.to_args()],
    limits~,
  )
  WasmProcessChannel::{ inner: channel, }
}

///|
/// The host end of a native WASM worker: a process channel that reads the
/// worker's report when its stdout ends, and raises the guest fault or the
/// refusal that the report names.
pub struct WasmProcessChannel {
  priv inner : @process.ProcessChannel
}

///|
/// The error for a worker whose stream ended: the fault or refusal of its
/// report, or `error` when it reported neither.
async fn WasmProcessChannel::ended(
  self : WasmProcessChannel,
  error : @worker.ChannelError,
) -> @worker.ChannelError {
  let stop = @async.protect_from_cancel(() => self.inner.close())
  @guest.WorkerEvent::ending_in(stop.stderr.bytes()).unwrap_or(error)
}

///|
pub extend WasmProcessChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
  bounds,
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn send(self, message) {
  self.inner.send(message) catch {
    @worker.WorkerClosed => raise self.ended(WorkerClosed)
    @worker.TransportFailed(text) => raise self.ended(TransportFailed(text))
    error => raise error
  }
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn receive(self) {
  self.inner.receive() catch {
    @worker.WorkerClosed => raise self.ended(WorkerClosed)
    error => raise error
  }
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn close(self) {
  self.inner.close()
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn abort(self, reason) {
  self.inner.abort(reason)
}

///|
/// The native engine enforces the memory ceiling, the instruction budget and
/// the per-call deadline.
pub impl @worker.Channel for WasmProcessChannel with fn bounds(_) {
  Some(@guest.engine_bounds())
}
