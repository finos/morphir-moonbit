///|
#cfg(target="js")
test "local flush rejects a FIFO and remains deadline bounded" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  let fifo = root + "/blocked"
  ignore(@platform.process("mkfifo", [fifo], root, "", 1000))
  let rejected = try {
    ignore(@platform.read_bytes(fifo))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let start = @platform.monotonic_seconds()
  assert_false(@platform.flush_file(fifo, b"record", 50))
  assert_true(@platform.monotonic_seconds() - start < 1.0)
  @platform.remove_file(fifo)
  @platform.remove_dir(root)
}
