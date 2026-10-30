///|
/// A Node worker thread and the events that the host waits for.
#external
priv type JsWorker

///|
/// Starts the entry module in a new worker thread with an empty environment.
/// `on_event` receives each message of the thread: kind 0 a response, 1 a
/// report event as JSON text, 2 the thread's exit with its code as text, 3
/// an uncaught error with its message. The thread's own stdout is drained and
/// dropped; its stderr goes to `on_stderr`.
extern "js" fn JsWorker::start(
  entry : String,
  abi : String,
  module_ : Bytes,
  request_bytes : Int32,
  response_bytes : Int32,
  call_ms : Int32,
  on_event : (Int32, Bytes, String) -> Unit,
  on_stderr : (Bytes) -> Unit,
) -> JsWorker =
  #| (entry, abi, module, requestBytes, responseBytes, callMs, onEvent, onStderr) => {
  #|   const {Worker} = process.getBuiltinModule('node:worker_threads');
  #|   const none = new Uint8Array(0);
  #|   const handle = {worker: null, code: -1, done: false, error: ''};
  #|   try {
  #|     handle.worker = new Worker(entry, {
  #|       workerData: {abi, module, requestBytes, responseBytes, callMs},
  #|       env: {}, stdout: true, stderr: true,
  #|     });
  #|   } catch (error) {
  #|     handle.error = error?.message ?? String(error);
  #|     handle.done = true;
  #|     handle.exited = Promise.resolve();
  #|     return handle;
  #|   }
  #|   const worker = handle.worker;
  #|   handle.exited = new Promise(resolve => worker.once('exit', code => {
  #|     handle.code = code; handle.done = true; onEvent(2, none, String(code)); resolve();
  #|   }));
  #|   worker.on('message', message => {
  #|     if (message?.kind === 'response' && message.bytes instanceof Uint8Array) onEvent(0, message.bytes, '');
  #|     else if (message?.kind === 'event' && typeof message.text === 'string') onEvent(1, none, message.text);
  #|   });
  #|   worker.on('error', error => onEvent(3, none, error?.message ?? String(error)));
  #|   worker.stdout.on('data', () => {});
  #|   worker.stderr.on('data', chunk => onStderr(new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.length)));
  #|   return handle;
  #| }

///|
/// Why the thread did not start, or "".
extern "js" fn JsWorker::start_error(self : JsWorker) -> String =
  #| (handle) => handle.error

///|
extern "js" fn JsWorker::post(self : JsWorker, bytes : Bytes) -> Unit =
  #| (handle, bytes) => { if (!handle.done) handle.worker.postMessage(bytes); }

///|
/// Terminates the thread; the promise resolves when it has terminated.
extern "js" fn JsWorker::terminate(
  self : JsWorker,
  _signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle) => handle.done ? handle.exited : handle.worker.terminate().then(() => handle.exited)

///|
/// Resolves when the thread has exited.
extern "js" fn JsWorker::exited(
  self : JsWorker,
  _signal : @js_async.AbortSignal,
) -> @js_async.Promise[Unit] =
  #| (handle) => handle.exited

///|
/// The thread's exit code, or -1 before its exit.
extern "js" fn JsWorker::exit_code(self : JsWorker) -> Int32 =
  #| (handle) => handle.done ? handle.code : -1

///|
/// The bytes of a file, or `None` with the reason in `error[0]`.
extern "js" fn read_file_ffi(
  path : String,
  error : FixedArray[String],
) -> Bytes =
  #| (path, error) => {
  #|   try {
  #|     const buffer = process.getBuiltinModule('node:fs').readFileSync(path);
  #|     return new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.length);
  #|   } catch (cause) { error[0] = cause?.message ?? String(cause); return new Uint8Array(0); }
  #| }

///|
fn read_file(path : String) -> Bytes raise @worker.LaunchError {
  let error : FixedArray[String] = [""]
  let bytes = read_file_ffi(path, error)
  guard error[0] == "" else {
    raise ArtifactUnreadable(Unreadable(detail=Some(error[0])))
  }
  bytes
}

///|
/// The path of `name` beside the JavaScript file that runs this code, from
/// the first frame of a stack trace, or "" when it cannot be found. The CLI
/// bundle runs this code, so `name` is beside the bundle.
extern "js" fn beside_script(name : String) -> String =
  #| (name) => {
  #|   const path = process.getBuiltinModule('node:path');
  #|   const {fileURLToPath} = process.getBuiltinModule('node:url');
  #|   const frames = String(new Error().stack ?? '').split('\n').slice(1);
  #|   for (const frame of frames) {
  #|     const match = /\(?((?:file:\/\/)?(?:[A-Za-z]:)?[^():\s]*\.[cm]?js):\d+:\d+\)?\s*$/.exec(frame.trim());
  #|     if (!match) continue;
  #|     try {
  #|       const script = match[1].startsWith('file://') ? fileURLToPath(match[1]) : match[1];
  #|       return path.join(path.dirname(script), name);
  #|     } catch { return ''; }
  #|   }
  #|   return '';
  #| }

///|
extern "js" fn file_exists(path : String) -> Bool =
  #| (path) => { try { return process.getBuiltinModule('node:fs').statSync(path).isFile(); } catch { return false; } }
