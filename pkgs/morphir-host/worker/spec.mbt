///|
/// A SHA-256 digest: 64 lowercase hexadecimal digits.
pub struct Sha256 {
  priv hex : String
} derive(Eq, Debug)

///|
pub extend Sha256 with Eq::{equal, not_equal}

///|
pub extend Sha256 with @debug.Debug::{to_repr}

///|
pub fn Sha256::parse(text : String) -> Sha256 raise ValueError {
  guard text.length() == 64 &&
    text.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) else {
    raise InvalidSha256(text)
  }
  { hex: text, }
}

///|
/// The digest of bytes the host has already read.
pub fn Sha256::of(bytes : Bytes) -> Sha256 {
  { hex: @identity.sha256(bytes), }
}

///|
pub impl Show for Sha256 with fn output(self, logger) {
  logger.write_string(self.hex)
}

///|
pub extend Sha256 with Show::{to_string, output}

///|
/// An absolute artifact location: a Unix path, a Windows drive path or a UNC
/// path. Relative paths are refused because a worker has no working directory
/// of the caller.
pub struct ArtifactPath {
  priv text : String
} derive(Eq, Debug)

///|
pub extend ArtifactPath with Eq::{equal, not_equal}

///|
pub extend ArtifactPath with @debug.Debug::{to_repr}

///|
pub fn ArtifactPath::parse(text : String) -> ArtifactPath raise ValueError {
  let drive = text.to_array()[:] is [c, ':', '\\' | '/', ..] &&
    c.is_ascii_alphabetic()
  guard (text.has_prefix("/") || text.has_prefix("\\\\") || drive) &&
    !text.contains_char('\u0000') else {
    raise InvalidArtifactPath(text)
  }
  { text, }
}

///|
pub impl Show for ArtifactPath with fn output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ArtifactPath with Show::{to_string, output}

///|
/// An artifact and the digest its bytes must have when the host runs them.
pub struct ArtifactRef {
  path : ArtifactPath
  sha256 : Sha256
} derive(Eq, Debug)

///|
pub extend ArtifactRef with Eq::{equal, not_equal}

///|
pub extend ArtifactRef with @debug.Debug::{to_repr}

///|
pub fn ArtifactRef::new(path : ArtifactPath, sha256 : Sha256) -> ArtifactRef {
  { path, sha256, }
}

///|
/// A host platform that a process artifact is built for.
pub(all) enum Platform {
  DarwinArm64
  DarwinX64
  LinuxArm64
  LinuxX64
  WindowsArm64
  WindowsX64
} derive(Eq, Debug)

///|
pub extend Platform with Eq::{equal, not_equal}

///|
pub extend Platform with @debug.Debug::{to_repr}

///|
let platforms : Array[Platform] = [
  DarwinArm64,
  DarwinX64,
  LinuxArm64,
  LinuxX64,
  WindowsArm64,
  WindowsX64,
]

///|
pub fn Platform::parse(text : String) -> Platform raise ValueError {
  match platforms.search_by(platform => platform.to_string() == text) {
    Some(index) => platforms[index]
    None => raise UnknownPlatform(text)
  }
}

///|
pub impl Show for Platform with fn output(self, logger) {
  logger.write_string(
    match self {
      DarwinArm64 => "darwin-arm64"
      DarwinX64 => "darwin-x64"
      LinuxArm64 => "linux-arm64"
      LinuxX64 => "linux-x64"
      WindowsArm64 => "windows-arm64"
      WindowsX64 => "windows-x64"
    },
  )
}

///|
pub extend Platform with Show::{to_string, output}

///|
/// The closed set of WASM guest ABIs the host can adapt.
pub(all) enum WasmAbi {
  ExtismKernelV1
  MorphirBytesV1
} derive(Eq, Debug)

///|
pub extend WasmAbi with Eq::{equal, not_equal}

///|
pub extend WasmAbi with @debug.Debug::{to_repr}

///|
pub fn WasmAbi::parse(text : String) -> WasmAbi raise ValueError {
  match text {
    "extism-kernel-v1" => ExtismKernelV1
    "morphir-bytes-v1" => MorphirBytesV1
    _ => raise UnknownWasmAbi(text)
  }
}

///|
pub impl Show for WasmAbi with fn output(self, logger) {
  logger.write_string(
    match self {
      ExtismKernelV1 => "extism-kernel-v1"
      MorphirBytesV1 => "morphir-bytes-v1"
    },
  )
}

///|
pub extend WasmAbi with Show::{to_string, output}

///|
/// How the host runs an artifact. Process arguments are opaque and are passed
/// to the worker unchanged. A WASM ABI, when declared, must agree with the
/// ABI classified from the module.
pub(all) enum WorkerRuntime {
  Process(platform~ : Platform, args~ : Array[String])
  Wasm(abi~ : WasmAbi?)
} derive(Eq, Debug)

///|
pub extend WorkerRuntime with Eq::{equal, not_equal}

///|
pub extend WorkerRuntime with @debug.Debug::{to_repr}

///|
/// The only input from which the host starts a worker. Its parts are
/// validated, so a specification always has a digest and exactly one runtime.
pub struct WorkerSpec {
  artifact : ArtifactRef
  runtime : WorkerRuntime
} derive(Eq, Debug)

///|
pub extend WorkerSpec with Eq::{equal, not_equal}

///|
pub extend WorkerSpec with @debug.Debug::{to_repr}

///|
pub fn WorkerSpec::new(
  artifact : ArtifactRef,
  runtime : WorkerRuntime,
) -> WorkerSpec {
  { artifact, runtime, }
}
