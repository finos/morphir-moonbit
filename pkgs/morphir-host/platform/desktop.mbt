///|
pub fn args() -> Array[String] {
  @env.args()
}

///|
pub fn environment() -> Map[String, String] {
  @env.get_env_vars()
}

///|
pub fn cwd() -> String {
  @env.current_dir().unwrap_or(".")
}

///|
pub fn read_bytes(path : String) -> Bytes raise {
  let length = size(path)
  if length < 0 || length > 16777216 {
    raise IOError("Unreadable file or file exceeds 16 MiB: " + path)
  }
  @fs.read_file_to_bytes(path)
}

///|
pub fn write(path : String, content : String) -> Unit raise {
  @fs.write_string_to_file(path, content)
}

///|
pub fn list(path : String) -> Array[String] raise {
  @fs.read_dir(path).to_owned()
}

///|
pub fn remove_file(path : String) -> Unit raise {
  @fs.remove_file(path)
}

///|
pub fn remove_dir(path : String) -> Unit raise {
  @fs.remove_dir(path)
}

///|
pub fn read(path : String) -> String raise {
  @utf8.decode(read_bytes(path)[:])
}

///|
pub fn write_bytes(path : String, content : Bytes) -> Unit raise {
  @fs.write_bytes_to_file(path, content)
}
