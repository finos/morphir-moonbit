///|
fn cstring(s : String) -> Bytes {
  @utf8.encode(s[:]) + b"\x00"
}

///|
#borrow(path)
extern "C" fn kind_c(path : Bytes) -> Int = "morphir_host_kind"

///|
#borrow(a, b)
extern "C" fn rename_c(a : Bytes, b : Bytes) -> Int = "morphir_host_rename"

///|
#borrow(text)
extern "C" fn stderr_c(text : Bytes) -> Unit = "morphir_host_stderr"

///|
extern "C" fn exit_c(code : Int) -> Unit = "morphir_host_exit"

///|
pub fn kind(path : String) -> Int raise {
  let result = kind_c(cstring(path))
  if result < 0 {
    raise IOError("Cannot inspect " + path)
  }
  result
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  check(rename_c(cstring(a), cstring(b)), "rename")
}

///|
pub fn stderr(text : String) -> Unit {
  stderr_c(cstring(text))
}

///|
pub fn exit(code : Int) -> Unit {
  exit_c(code)
}

///|
pub fn arguments() -> Array[String] {
  args()[1:].to_owned()
}

///|
extern "C" fn system_c() -> Int = "morphir_host_system"

///|
pub fn system_type() -> String {
  match system_c() {
    0 => "macos"
    1 => "windows"
    _ => "linux"
  }
}

///|
#borrow(path)
extern "C" fn size_c(path : Bytes) -> Int = "morphir_host_size"

///|
fn size(path : String) -> Int {
  size_c(cstring(path))
}

///|
pub fn mkdir(path : String) -> Unit raise {
  @fs.create_dir(path)
}
