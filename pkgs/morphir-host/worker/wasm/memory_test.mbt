///|
fn capped(bytes : Bytes, pages : Int32) -> @wasm.WasmModule raise {
  read(bytes).with_memory_ceiling(@wasm.MemoryCeiling::of_pages(pages))
}

///|
test "the restricted ceiling is 256 MiB" {
  assert_eq(@wasm.MemoryCeiling::restricted().pages(), 4096)
}

///|
test "memory ceiling: a module without a maximum gets the ceiling" {
  let module_ = capped(@fixtures.echo_guest(), 4096)
  guard module_.memories() is [memory] else { fail("not one memory") }
  assert_eq(memory.minimum, 1L)
  assert_eq(memory.maximum, Some(4096L))
  // The rewritten bytes read back the same, with the same imports and exports.
  let again = read(module_.bytes())
  assert_eq(again.memories(), module_.memories())
  assert_eq(again.imports(), read(@fixtures.echo_guest()).imports())
  assert_eq(again.exports().map(item => item.name), ["handle", "memory"])
}

///|
test "memory ceiling: a larger maximum is lowered and a smaller one kept" {
  let larger = @fixtures.module_(
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
    memory=@fixtures.Memory::new(2, maximum=65536),
  )
  assert_eq(capped(larger, 4096).memories()[0].maximum, Some(4096L))
  let smaller = @fixtures.module_(
    functions=[
      @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
    ],
    memory=@fixtures.Memory::new(2, maximum=16),
  )
  assert_eq(capped(smaller, 4096).memories()[0].maximum, Some(16L))
  // A module without a defined memory is unchanged.
  let plain = @fixtures.module_(functions=[
    @fixtures.DefinedFunction::new(export_name="handle", b"\x41\x00"),
  ])
  assert_eq(capped(plain, 4096).bytes(), plain)
}

///|
test "memory ceiling: an initial memory above the ceiling is refused" {
  let big = @fixtures.module_(memory=@fixtures.Memory::new(5000))
  let refusal = try capped(big, 4096) catch {
    @wasm.InitialAboveCeiling(initial~, ceiling~) => Some((initial, ceiling))
    _ => None
  } noraise {
    _ => None
  }
  assert_eq(refusal, Some((5000L, 4096)))
}
