///|
/// Explicit host capability. The caller supplies the built binary and its
/// receipt; binary verification does not attest a caller's build provenance.
pub struct NativeTelemetry {
  priv program : String
  priv helper : String
  priv endpoint : String
  priv protocol : String
  priv timeout : Int
  priv binary_identity : String
}

///|
pub fn NativeTelemetry::new(
  program : String,
  helper : String,
  endpoint : String,
  protocol : String,
  pin : Json,
  timeout? : Int = 1000,
) -> NativeTelemetry raise {
  let platform = if @platform.system_type() == "macos" {
    "darwin"
  } else {
    @platform.system_type()
  }
  if !@platform.process_supported() ||
    !((platform == "darwin" && @platform.architecture() == "arm64") ||
    (platform == "linux" && @platform.architecture() == "x64")) {
    raise @config.Invalid("observability.native_adapter_host_unavailable")
  }
  if program == "" ||
    helper == "" ||
    endpoint == "" ||
    endpoint.length() > 4096 ||
    !(endpoint.has_prefix("http://") || endpoint.has_prefix("https://")) ||
    endpoint.has_suffix("/") ||
    protocol != "http/json" ||
    timeout < 1 ||
    timeout > 5000 {
    raise @config.Invalid("observability.native_adapter_configuration")
  }
  if build_text(pin, "profile") != "morphir-native-otel-pin-v1" ||
    build_text(pin, "platform") != platform ||
    build_text(pin, "arch") != @platform.architecture() ||
    build_text(pin, "compilerVersion") != "0.10.14+7d59c7ec9" ||
    build_text(pin, "otelArchiveIdentity") !=
    "51c7ad32e1344cae45cedfa8d5ee3836d3e22f17ff4796a45a8394917568033f" {
    raise @config.Invalid("observability.native_adapter_pin")
  }
  let binary_identity = build_text(pin, "binaryIdentity")
  if @platform.kind(program) != 1 ||
    binary_identity.length() != 64 ||
    binary_identity != @identity.sha256(@platform.read_bytes(program)) ||
    @platform.kind(helper) != 1 {
    raise @config.Invalid("observability.native_adapter_identity")
  }
  { program, helper, endpoint, protocol, timeout, binary_identity, }
}

///|
pub fn TelemetrySession::flush_native(
  self : TelemetrySession,
  adapter : NativeTelemetry,
  node : String,
) -> Unit {
  self.flush_to_process(
    node,
    adapter.helper,
    adapter.program,
    [adapter.endpoint, adapter.protocol, adapter.timeout.to_string()],
    timeout=adapter.timeout,
    program_identity=Some(adapter.binary_identity),
    clear_otel_environment=true,
  )
}
