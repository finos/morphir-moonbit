///|
/// A Node child process and the events that the host waits for. The JS object
/// records the exit status when the `exit` event arrives.
#external
priv type Child

///|
/// Starts `program` in a new process group (`detached: true`) with three
/// pipes, a hidden window on Windows, the given working directory and an
/// environment that holds only `SystemRoot` on Windows and nothing elsewhere.
/// The promise resolves on the `spawn` event and rejects on a start failure.
/// Every stderr chunk goes to `on_stderr` as it arrives.
extern "js" fn Child::spawn(
  program : String,
  args : FixedArray[String],
  cwd : String,
  on_stderr : (Bytes) -> Unit,
) -> @js_async.Promise[Child] =
  #| (program, args, cwd, onStderr) => new Promise((resolve, reject) => {
  #|   const {spawn} = process.getBuiltinModule('node:child_process');
  #|   const env = process.platform === 'win32' && process.env.SystemRoot ? {SystemRoot: process.env.SystemRoot} : {};
  #|   let child;
  #|   try {
  #|     child = spawn(program, Array.from(args), {cwd, env, detached: true, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true});
  #|   } catch (error) { reject(error); return; }
  #|   const handle = {child, pid: 0, status: null};
  #|   handle.exit = new Promise(done => child.once('exit', (code, signal) => { handle.status = {code, signal}; done(); }));
  #|   handle.stderrDone = new Promise(done => child.stderr.once('close', done));
  #|   child.stdin.on('error', () => {});
  #|   child.stderr.on('data', chunk => onStderr(new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.length)));
  #|   child.once('spawn', () => { handle.pid = child.pid; child.on('error', () => {}); resolve(handle); });
  #|   child.once('error', error => reject(error));
  #| })

///|
extern "js" fn Child::pid(self : Child) -> Int32 =
  #| (handle) => handle.pid

///|
/// The worker's stdout as a web stream (`Readable.toWeb`).
extern "js" fn Child::stdout(self : Child) -> @js_async.JsReadableStream =
  #| (handle) => process.getBuiltinModule('node:stream').Readable.toWeb(handle.child.stdout)

///|
/// Writes bytes to the worker's stdin. The promise resolves when Node has
/// written them and rejects on a write error or an abort.
extern "js" fn Child::write(
  self : Child,
  bytes : Bytes,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle, bytes, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   handle.child.stdin.write(bytes, error => {
  #|     signal.removeEventListener('abort', abort);
  #|     if (error) reject(error); else resolve(undefined);
  #|   });
  #| })

///|
/// Ends the worker's stdin, so the worker reads the end of its input.
extern "js" fn Child::end_input(self : Child) -> Unit =
  #| (handle) => { try { handle.child.stdin.end(); } catch {} }

///|
/// Resolves when the worker has exited, or at once if it already has.
extern "js" fn Child::exited(
  self : Child,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   handle.exit.then(() => { signal.removeEventListener('abort', abort); resolve(undefined); });
  #| })

///|
/// Resolves when the worker's stderr has closed.
extern "js" fn Child::stderr_closed(
  self : Child,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle, signal) => new Promise((resolve, reject) => {
  #|   if (signal.aborted) { reject(signal.reason); return; }
  #|   const abort = () => reject(signal.reason);
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   handle.stderrDone.then(() => { signal.removeEventListener('abort', abort); resolve(undefined); });
  #| })

///|
/// The exit code, or -1 when the worker has not exited or exited by a signal.
extern "js" fn Child::exit_code(self : Child) -> Int32 =
  #| (handle) => handle.status && handle.status.code !== null ? handle.status.code : -1

///|
/// The number of the signal that ended the worker, or 0.
extern "js" fn Child::exit_signal(self : Child) -> Int32 =
  #| (handle) => {
  #|   const name = handle.status && handle.status.signal;
  #|   if (!name) return 0;
  #|   return process.getBuiltinModule('node:os').constants.signals[name] ?? 0;
  #| }

///|
extern "js" fn host_is_windows() -> Bool =
  #| () => process.platform === 'win32'

///|
/// Sends SIGKILL to the process group: 0 when it was signalled, 1 when the
/// group no longer exists, 2 when the host may not signal it.
extern "js" fn signal_group(pid : Int32) -> Int32 =
  #| (pid) => {
  #|   try { process.kill(-pid, 'SIGKILL'); return 0; }
  #|   catch (error) { return error.code === 'ESRCH' ? 1 : 2; }
  #| }

///|
/// Whether the process group still has a member, a zombie included.
extern "js" fn group_present(pid : Int32) -> Bool =
  #| (pid) => {
  #|   try { process.kill(-pid, 0); return true; }
  #|   catch (error) { return error.code !== 'ESRCH'; }
  #| }

///|
/// Runs `taskkill /PID pid /T /F` and resolves with its exit code, or -1 when
/// it cannot start.
extern "js" fn kill_tree(
  pid : Int32,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Int32] =
  #| (pid, signal) => new Promise((resolve, reject) => {
  #|   const {spawn} = process.getBuiltinModule('node:child_process');
  #|   const taskkill = (process.env.SystemRoot || 'C:\\Windows') + '\\System32\\taskkill.exe';
  #|   const killer = spawn(taskkill, ['/PID', String(pid), '/T', '/F'], {stdio: 'ignore', windowsHide: true});
  #|   const abort = () => { killer.kill(); reject(signal.reason); };
  #|   signal.addEventListener('abort', abort, {once: true});
  #|   killer.once('error', () => { signal.removeEventListener('abort', abort); resolve(-1); });
  #|   killer.once('exit', code => { signal.removeEventListener('abort', abort); resolve(code ?? -1); });
  #| })

///|
extern "js" fn remove_directory(path : String) -> Unit =
  #| (path) => {
  #|   try { process.getBuiltinModule('node:fs').rmSync(path, {recursive: true, force: true}); } catch {}
  #| }

///|
/// The result of reading an artifact without following a symbolic link.
#external
priv type ArtifactRead

///|
/// Opens the artifact with `O_NOFOLLOW` (and `O_NONBLOCK`, so a FIFO cannot
/// block), checks with `fstat` that it is a regular file within `limit`
/// bytes, and reads it through the same descriptor. Windows has no
/// `O_NOFOLLOW`; there the host refuses a link that `lstat` reports.
extern "js" fn read_artifact(path : String, limit : Int32) -> ArtifactRead =
  #| (path, limit) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   let fd;
  #|   try {
  #|     if (process.platform === 'win32') {
  #|       if (fs.lstatSync(path).isSymbolicLink()) return {problem: 1};
  #|       fd = fs.openSync(path, 'r');
  #|     } else {
  #|       const {O_RDONLY, O_NOFOLLOW, O_NONBLOCK} = fs.constants;
  #|       fd = fs.openSync(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  #|     }
  #|     const stat = fs.fstatSync(fd);
  #|     if (!stat.isFile()) return {problem: 2};
  #|     if (stat.size > limit) return {problem: 3};
  #|     const bytes = fs.readFileSync(fd);
  #|     return {problem: 0, bytes: new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.length)};
  #|   } catch (error) {
  #|     return error.code === 'ELOOP' ? {problem: 1} : {problem: 4, detail: String(error.message)};
  #|   } finally {
  #|     if (fd !== undefined) { try { fs.closeSync(fd); } catch {} }
  #|   }
  #| }

///|
/// 0 when the read succeeded, 1 a symbolic link, 2 not a regular file, 3 too
/// large, 4 unreadable.
extern "js" fn ArtifactRead::problem_code(self : ArtifactRead) -> Int32 =
  #| (read) => read.problem

///|
extern "js" fn ArtifactRead::detail(self : ArtifactRead) -> String =
  #| (read) => read.detail ?? ''

///|
extern "js" fn ArtifactRead::bytes(self : ArtifactRead) -> Bytes =
  #| (read) => read.bytes

///|
/// Creates a private directory (mode 0700) in the staging layout: an empty
/// `work` directory and a `bin` directory (both 0700) that holds a new file
/// `name` that only its owner can read and execute. Returns the directory, or
/// "" when a step fails; a failed step leaves no directory behind.
extern "js" fn write_private_copy(
  name : String,
  bytes : Bytes,
  bin : String,
  work : String,
) -> String =
  #| (name, bytes, bin, work) => {
  #|   const fs = process.getBuiltinModule('node:fs'), os = process.getBuiltinModule('node:os'), path = process.getBuiltinModule('node:path');
  #|   let directory = '';
  #|   try {
  #|     directory = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'morphir-worker-'));
  #|     fs.mkdirSync(path.join(directory, work), {mode: 0o700});
  #|     fs.mkdirSync(path.join(directory, bin), {mode: 0o700});
  #|     fs.writeFileSync(path.join(directory, bin, name), bytes, {mode: 0o500, flag: 'wx'});
  #|     return directory;
  #|   } catch {
  #|     if (directory) { try { fs.rmSync(directory, {recursive: true, force: true}); } catch {} }
  #|     return '';
  #|   }
  #| }

///|
/// The host's target triple, or "" for a host without a release platform.
extern "js" fn host_triple() -> String =
  #| () => {
  #|   const arch = {arm64: 'aarch64', x64: 'x86_64'}[process.arch];
  #|   if (!arch) return '';
  #|   switch (process.platform) {
  #|     case 'darwin': return arch + '-apple-darwin';
  #|     case 'win32': return arch + '-pc-windows-msvc';
  #|     case 'linux': {
  #|       const glibc = process.report?.getReport?.()?.header?.glibcVersionRuntime;
  #|       return arch + '-unknown-linux-' + (glibc ? 'gnu' : 'musl');
  #|     }
  #|     default: return '';
  #|   }
  #| }

///|
/// Lets the host exit while a worker whose stop it could not confirm still
/// runs: destroys the worker's pipes and drops Node's reference to it.
extern "js" fn Child::release(self : Child) -> Unit =
  #| (handle) => {
  #|   for (const stream of [handle.child.stdin, handle.child.stdout, handle.child.stderr]) { try { stream.destroy(); } catch {} }
  #|   handle.child.unref();
  #| }
