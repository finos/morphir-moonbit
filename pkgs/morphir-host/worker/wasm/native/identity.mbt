///|
/// The version of the contract between a WASM launcher and its worker mode:
/// the arguments, the frames and the stderr report.
pub const WORKER_CONTRACT : String = "morphir-wasm-worker/0.1.0"

///|
/// The version of the host library that this worker mode belongs to.
const HOST_VERSION : String = "0.1.0"

///|
/// The identity of a CLI build for its worker mode: a SHA-256 over the worker
/// contract, the host version, the SHA-256 of the Extism kernel and the
/// engine's features. The host passes its identity, and a worker of another
/// identity refuses to serve.
///
/// The identity comes from constants, because builds have no stamp. Two
/// development builds of the same version, kernel and engine features share
/// an identity.
pub struct BuildIdentity {
  priv digest : @worker.Sha256
} derive(Eq, Debug)

///|
pub extend BuildIdentity with Eq::{equal, not_equal}

///|
pub extend BuildIdentity with @debug.Debug::{to_repr}

///|
/// The identity of this build.
pub fn BuildIdentity::current() -> BuildIdentity {
  let features = @engine.Engine::default()
    .features()
    .map(feature => feature.name())
    .join(",")
  let text = "\{WORKER_CONTRACT}\nhost \{HOST_VERSION}\nkernel \{@kernel.sha256()}\nfeatures \{features}\n"
  { digest: @worker.Sha256::of(@utf8.encode(text)), }
}

///|
/// An identity in its text form, 64 lowercase hexadecimal digits.
pub fn BuildIdentity::parse(
  text : String,
) -> BuildIdentity raise @worker.ValueError {
  { digest: @worker.Sha256::parse(text), }
}

///|
pub impl Show for BuildIdentity with fn output(self, logger) {
  self.digest.output(logger)
}

///|
pub extend BuildIdentity with Show::{to_string, output}
