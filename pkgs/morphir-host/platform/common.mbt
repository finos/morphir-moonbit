///|
pub(all) suberror IOError {
  IOError(String)
}

///|
#cfg(not(target="wasm-gc"))
fn check(code : Int, operation : String) -> Unit raise {
  if code != 0 {
    raise IOError(operation + ": host error " + code.to_string())
  }
}

///|
#cfg(not(target="wasm-gc"))
pub fn bytes_supported() -> Bool {
  true
}
