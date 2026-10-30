///|
/// The most bytes of IR that one session's cache holds.
const IR_CACHE_BYTES : Int32 = 16777216

///|
/// The most bytes of Extism variables that one session holds.
const VARIABLE_BYTES : Int32 = 1048576

///|
/// An `extism-kernel-v1` guest: one plugin instance for the session. Each
/// request is one `handle` call with the request bytes as input, and the
/// response is the kernel output. Notifications are not delivered; `exit`
/// ends the instance. The host functions follow the WASM-4 policy.
pub struct ExtismGuest {
  priv plugin : @extism.Plugin
  priv handle : @extism.ExportName
  priv output : (GuestOutput) -> Unit
  priv request_limit : Int32
  priv mut state : State
}

///|
fn ExtismGuest::fail(
  self : ExtismGuest,
  fault : @worker.GuestFault,
) -> GuestError {
  self.state = Failed
  Faulted(fault)
}

///|
fn log_level(level : @extism.LogLevel) -> LogLevel {
  match level {
    Trace => Trace
    Debug => Debug
    Info => Info
    Warn => Warn
    Error => Error
  }
}

///|
fn host_error(name : String, text : String) -> @engine.HostError {
  HostError("\{name}: \{text}")
}

///|
fn read_text(
  context : @extism.CallContext,
  name : String,
  offset : Int64,
) -> String raise @engine.HostError {
  let bytes = context.read(@extism.Handle::parse(offset)) catch {
    _ => raise host_error(name, "no block at \{offset}")
  }
  @utf8.decode(bytes) catch {
    _ => raise host_error(name, "the text is not valid UTF-8")
  }
}

///|
fn allocate(
  context : @extism.CallContext,
  name : String,
  bytes : Bytes,
) -> Array[@engine.Value] raise @engine.HostError {
  let handle = context.allocate(bytes[:]) catch {
    _ =>
      raise host_error(
        name,
        "the kernel has no room for \{bytes.length()} bytes",
      )
  }
  [I64(handle.offset())]
}

///|
/// The four Morphir host functions in `extism:host/user`, as for restricted
/// generation in the Rust host: the workspace is an empty private directory,
/// the IR cache lives only for the session and `morphir_log` becomes output.
fn morphir_functions(
  services : GuestServices,
) -> Array[@extism.HostFunction] raise @extism.NameError {
  let user = @extism.Namespace::parse(@wasm.extism_user_namespace)
  let cache : Map[String, Bytes] = Map([])
  let mut cached_bytes = 0
  let function = (name, params, results, body) => {
    @extism.HostFunction::new(
      user,
      @extism.FunctionName::parse(name),
      @engine.Signature::new(params, results),
      body,
    )
  }
  [
    function("morphir_get_workspace_info", [], [I64], (context, _) => {
      let info : Json = { "root": services.workspace_root, "output_dir": "" }
      allocate(
        context,
        "morphir_get_workspace_info",
        @utf8.encode(info.stringify()),
      )
    }),
    function("morphir_cache_ir", [I64, I64], [], (context, args) => {
      let name = "morphir_cache_ir"
      guard args is [I64(key), I64(ir)] else {
        raise host_error(name, "bad arguments")
      }
      let key = read_text(context, name, key)
      let value = context.read(@extism.Handle::parse(ir)) catch {
        _ => raise host_error(name, "no block at \{ir}")
      }
      let previous = cache.get(key).map(bytes => bytes.length()).unwrap_or(0)
      guard cached_bytes - previous + value.length() <= IR_CACHE_BYTES else {
        raise host_error(name, "the IR cache is over \{IR_CACHE_BYTES} bytes")
      }
      cached_bytes = cached_bytes - previous + value.length()
      cache[key] = value
      []
    }),
    function("morphir_get_cached_ir", [I64], [I64], (context, args) => {
      let name = "morphir_get_cached_ir"
      guard args is [I64(key)] else { raise host_error(name, "bad arguments") }
      let key = read_text(context, name, key)
      allocate(context, name, cache.get(key).unwrap_or(b"null"))
    }),
    function("morphir_log", [I64, I64], [], (context, args) => {
      let name = "morphir_log"
      guard args is [I64(level), I64(message)] else {
        raise host_error(name, "bad arguments")
      }
      (services.output)(
        MorphirLog(
          level=read_text(context, name, level),
          read_text(context, name, message),
        ),
      )
      []
    }),
  ]
}

///|
/// The WASI preview 1 sandbox of WASM-4: no preopens, empty arguments,
/// environment and stdin, the host's clocks and random bytes, and stdout and
/// stderr as output.
fn sandbox(services : GuestServices) -> @wasi.Sandbox {
  let random = @random.Rand()
  let started = @env.now()
  let nanoseconds = (milliseconds : UInt64) => milliseconds * 1000000UL
  @wasi.Sandbox::new()
  .clock({
    time: id => {
      match id {
        Realtime => nanoseconds(@env.now())
        _ => nanoseconds(@env.now() - started)
      }
    },
    resolution: _ => nanoseconds(1UL),
  })
  .random(count => {
    Bytes::makei(count, _ => {
      random.uint(limit=256).reinterpret_as_int().to_byte()
    })
  })
  .stdout(bytes => (services.output)(Stdout(bytes.to_owned())))
  .stderr(bytes => (services.output)(Stderr(bytes.to_owned())))
}

///|
fn ExtismGuest::load(
  prepared : @wasm.PreparedModule,
  call~ : CallBounds,
  limits~ : @worker.Limits,
  ceiling~ : @wasm.MemoryCeiling,
  services~ : GuestServices,
) -> ExtismGuest raise @worker.LaunchError {
  let (budget, deadline) = call.engine()
  try {
    let pages = @engine.PageCount::parse(ceiling.pages())
    let plugin_limits = @extism.Limits::default()
      .plugin_memory(pages)
      .deadline(deadline)
    let plugin_limits = match budget {
      Some(budget) => plugin_limits.budget(budget)
      None => plugin_limits
    }
    let policy = @extism.Policy::default()
      .config(Empty)
      .variables(Session(@extism.ByteLimit::parse(VARIABLE_BYTES.to_int64())))
      .logging(
        Sink(Trace, (level, text) => {
          (services.output)(Log(log_level(level), text))
        }),
      )
      .http(Deny)
    let mut manifest = @extism.Manifest::new(prepared.module_.bytes())
      .limits(plugin_limits)
      .policy(policy)
      .wasi(sandbox(services))
    for function in morphir_functions(services) {
      manifest = manifest.register(function)
    }
    let plugin = @extism.Plugin::load(manifest)
    {
      plugin,
      handle: @extism.ExportName::parse(@wasm.handle_export),
      output: services.output,
      request_limit: limits.request_bytes,
      state: Ready,
    }
  } catch {
    @extism.UnlinkedImport(module_name, name)
    | @extism.WrongSignature(module_name, name) =>
      raise AbiUnsupported(@worker.ImportName::new(module_name, name))
    @extism.LoadError::Engine(FeatureUnsupported(feature)) =>
      raise WasmFeatureUnsupported(feature=Some(feature.name()))
    error =>
      raise LaunchFailed("the guest did not load: \{@debug.to_string(error)}")
  }
}

///|
/// The guest fault for a plugin call error.
fn ExtismGuest::call_fault(
  self : ExtismGuest,
  error : @extism.CallError,
) -> @worker.GuestFault {
  match error {
    Plugin(code, text) => Failure("the guest set an error (\{code}): \{text}")
    Exit(code) => Failure("the guest exited with code \{code} during a call")
    Denied({ function, method_, url, }) => {
      if function == "http_request" {
        (self.output)(
          RefusedHttp(verb=method_.unwrap_or("GET"), url=url.unwrap_or("")),
        )
      }
      Failure("\{function} was refused: the guest has no network access")
    }
    HostFunction(name, text) => Failure("host function \{name} failed: \{text}")
    MemoryLimit(kind) =>
      MemoryLimit("\{@debug.to_string(kind)} reached its ceiling")
    Limit(name) => Failure("the guest reached the limit \{name}")
    Engine(error) | Initialization(error) => call_fault(error)
    UnknownExport(name) => Failure("the module exports no function \{name}")
  }
}

///|
/// Whether a message is a notification, and whether it is `exit`.
fn notification(request : Bytes) -> (Bool, Bool) raise @json.ParseError {
  guard @json.parse(@utf8.decode_lossy(request)) is Object(fields) else {
    return (false, false)
  }
  if fields.contains("id") {
    return (false, false)
  }
  (true, fields.get("method") is Some(String("morphir.exit")))
}

///|
pub extend ExtismGuest with Guest::{exchange}

///|
/// Calls `handle` once for a request, with the request as input, and returns
/// the kernel output. A notification is not delivered; `exit` ends the
/// instance.
pub impl Guest for ExtismGuest with fn exchange(self, request) {
  match self.state {
    Ready => ()
    Exited => raise Faulted(Failure("the guest has exited"))
    Failed => raise Faulted(Failure("the guest failed before"))
  }
  guard request.length() <= self.request_limit else {
    raise self.fail(Failure("the request is over \{self.request_limit} bytes"))
  }
  guard valid_utf8(request) else {
    raise self.fail(Failure("the request is not valid UTF-8"))
  }
  let (is_notification, is_exit) = notification(request) catch {
    _ => raise self.fail(Failure("the message is not JSON"))
  }
  if is_exit {
    self.state = Exited
    return Exit
  }
  if is_notification {
    return Notified
  }
  let response = self.plugin.call(self.handle, request[:]) catch {
    error => raise self.fail(self.call_fault(error))
  }
  guard response.length() > 0 else {
    raise self.fail(Failure("the guest gave no response to a request"))
  }
  guard valid_utf8(response) else {
    raise self.fail(Failure("the response is not valid UTF-8"))
  }
  Response(response)
}
