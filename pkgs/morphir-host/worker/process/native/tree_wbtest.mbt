///|
/// A tree that the host signals but that never reports itself gone, like a
/// process stuck in the kernel.
priv struct Stuck {
  inner : &Tree
}

///|
impl Tree for Stuck with fn terminate(self) {
  self.inner.terminate()
}

///|
impl Tree for Stuck with fn kill(self) {
  self.inner.kill()
}

///|
impl Tree for Stuck with fn state(_self) {
  Live
}

///|
impl Tree for Stuck with fn release(self) {
  self.inner.release()
}

///|
#cfg(not(platform="windows"))
async test "a tree that cannot be confirmed gone is an unconfirmed stop" {
  let path = @fs.realpath("worker/process/native/fixtures/worker.sh")
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Posix)),
    @worker.Sha256::of(@fs.read_file(path).binary()),
  )
  let staged = stage(artifact)
  let spawned = spawn(staged, ["stubborn"])
  let channel = ProcessChannel::new(
    { ..spawned, tree: Stuck::{ inner: spawned.tree, }, },
    staged,
    @worker.Limits::host(),
    grace_ms=2000,
    confirm_ms=300,
  )
  let stop = channel.abort(Deadline)
  assert_true(stop.status is Unconfirmed(Deadline))
  // The host keeps the private directory while the tree may still use it.
  assert_true(@fs.exists(staged.directory()))
  assert_true(spawned.tree.state() is Gone)
  unstage(staged)
}

///|
async test "stop_tree kills a tree that outlives the gentle step" {
  let calls = []
  let tree : &Tree = Stuck::{ inner: Recorder::{ calls, }, }
  let confirmed = stop_tree(tree, _ => false, confirm_ms=20)
  assert_true(!confirmed)
  assert_eq(calls, ["terminate", "kill"])
}

///|
priv struct Recorder {
  calls : Array[String]
}

///|
impl Tree for Recorder with fn terminate(self) {
  self.calls.push("terminate")
}

///|
impl Tree for Recorder with fn kill(self) {
  self.calls.push("kill")
}

///|
impl Tree for Recorder with fn state(_self) {
  Gone
}

///|
impl Tree for Recorder with fn release(_self) {
  ()
}
