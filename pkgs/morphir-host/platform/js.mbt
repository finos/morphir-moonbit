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

///|
pub extern "js" fn architecture() -> String =
  #| () => process.arch

///|
pub fn process_supported() -> Bool {
  true
}

///|
#module("node:fs")
extern "js" fn mkdtemp(prefix : String) -> String = "mkdtempSync"

///|
#module("node:os")
extern "js" fn tmpdir() -> String = "tmpdir"

///|
pub fn temporary() -> String raise {
  mkdtemp(tmpdir() + "/morphir-toolchain-")
}

///|
#external
priv type Process

///|
#module("node:child_process")
extern "js" fn spawn(
  program : String,
  args : FixedArray[String],
  options : Process,
) -> Process = "spawnSync"

///|
extern "js" fn execute_js(
  spawn : (String, FixedArray[String], Process) -> Process,
  program : String,
  args : FixedArray[String],
  cwd : String,
  home : String,
  timeout : Int,
) -> String =
  #| (spawn,program,args,cwd,home,timeout) => { const env={...process.env}; if(home) { env.MOON_HOME=home; env.PATH=home+'/bin'+(process.platform==='win32'?';':':')+(env.PATH||''); } const r=spawn(program,args,{cwd,env,encoding:'utf8',timeout,maxBuffer:16777216,windowsHide:true}); return JSON.stringify({exitCode:r.error ? (r.error.code==='ETIMEDOUT'?124:-1) : (r.status??-1),stdout:r.stdout||'',stderr:(r.stderr||'')+(r.error ? r.error.message : '')}); }

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int,
) -> Json raise {
  @json.parse(
    execute_js(spawn, program, FixedArray::from_array(args), cwd, home, timeout),
  )
}

///|
pub extern "js" fn monotonic_seconds() -> Double = "() => Number(process.hrtime.bigint()) / 1e9"

///|
pub extern "js" fn wall_seconds() -> Double = "() => Date.now() / 1000"

///|
#module("node:crypto")
pub extern "js" fn observation_id() -> String = "randomUUID"
