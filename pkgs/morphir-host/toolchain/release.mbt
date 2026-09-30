///|
// SHA-256 of the official versioned archives, retrieved 2026-09-30.
let core_digest : String = "6f18b8fdea18f85e628a75e4a1bd3977c5a5c9c6a836fd8824192b0e6bd91b14"

///|
fn binary_digest(target : String) -> String raise {
  match target {
    "darwin-aarch64" =>
      "20967f9389ac54508899ee2fc051a3470d051452bac5818a9696ed4c144f3ec3"
    "linux-x86_64" =>
      "9226694de9ff978db1ecf820b7710c4224e84ec7a76b19a222d96f0cd4e31b6a"
    _ => raise ToolchainError("No archive digest for " + target)
  }
}
