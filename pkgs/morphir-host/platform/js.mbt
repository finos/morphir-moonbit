///|
#external
priv type Stats

///|
#module("node:fs")
extern "js" fn lstat(path : String) -> Stats = "lstatSync"

///|
#module("node:fs")
extern "js" fn rename_sync(a : String, b : String) -> Unit = "renameSync"

///|
extern "js" fn kind_js(stat : (String) -> Stats, path : String) -> Int =
  #| (stat,path) => { try { const s = stat(path); return s.isSymbolicLink() ? 3 : s.isDirectory() ? 2 : s.isFile() ? 1 : 4; } catch(e) { return e.code === 'ENOENT' || e.code === 'ENOTDIR' ? 0 : -1; } }

///|
extern "js" fn rename_js(
  rename : (String, String) -> Unit,
  a : String,
  b : String,
) -> Int =
  #| (rename,a,b) => { try { rename(a,b); return 0; } catch { return -1; } }

///|
pub fn kind(path : String) -> Int raise {
  let result = kind_js(lstat, path)
  if result < 0 {
    raise IOError("Cannot inspect " + path)
  }
  result
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  check(rename_js(rename_sync, a, b), "rename")
}

///|
pub extern "js" fn stderr(text : String) -> Unit =
  #| text => process.stderr.write(text)

///|
pub extern "js" fn exit(code : Int) -> Unit =
  #| code => { process.exitCode = code; }

///|
pub fn arguments() -> Array[String] {
  args()[2:].to_owned()
}

///|
pub extern "js" fn system_type() -> String =
  #| () => process.platform === 'darwin' ? 'macos' : process.platform === 'win32' ? 'windows' : 'linux'

///|
extern "js" fn size_js(stat : (String) -> Stats, path : String) -> Int =
  #| (stat,path) => { try { return Math.min(stat(path).size,16777217); } catch { return -1; } }

///|
fn size(path : String) -> Int {
  size_js(lstat, path)
}

///|
#module("node:fs")
extern "js" fn mkdir_sync(path : String) -> Unit = "mkdirSync"

///|
extern "js" fn mkdir_js(create : (String) -> Unit, path : String) -> Int =
  #| (create,path) => { try { create(path); return 0; } catch { return -1; } }

///|
pub fn mkdir(path : String) -> Unit raise {
  check(mkdir_js(mkdir_sync, path), "exclusive mkdir " + path)
}
