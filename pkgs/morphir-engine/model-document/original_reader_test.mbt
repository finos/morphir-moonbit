///|
test "retained original reader copies bounded binary chunks from the defensive owner" {
  let backing : FixedArray[Byte] = [0xef, 0xbb, 0xbf, 0x0d, 0x0a, 0x00, 0xff]
  let inventory = @document.OriginalInventory::from_connected(
    Map([("model.ion", backing.unsafe_reinterpret_as_bytes())]),
    [],
    NotReported,
  )
  backing[0] = 0x00
  let path = @document.OriginalPath::parse("model.ion", profile=Connected)
  guard inventory.open_file(path) is Some(reader) else {
    abort("retained file must open")
  }
  assert_eq(reader.byte_length(), 7UL)
  assert_eq(reader.position(), 0UL)
  match reader.read_chunk() {
    Chunk(bytes, next) => {
      assert_eq(bytes, b"\xef\xbb\xbf\r\n\x00\xff")
      assert_eq(next.position(), 7UL)
      assert_true(next.read_chunk() is EndOfFile)
      // A cursor is an immutable view; reading it does not consume or advance
      // another caller's view of the same retained owner.
      assert_eq(reader.position(), 0UL)
      match reader.read_chunk() {
        Chunk(again, _) => assert_eq(again, bytes)
        EndOfFile => abort("original cursor must remain readable")
      }
    }
    EndOfFile => abort("nonempty file must return a chunk")
  }
}

///|
test "retained original reader preserves the 64 KiB boundary and exact remaining bytes" {
  let bytes = Bytes::from_array(Array::makei(65539, i => (i % 256).to_byte()))
  let inventory = @document.OriginalInventory::from_connected(
    Map([("opaque.bin", bytes)]),
    [],
    NotReported,
  )
  let path = @document.OriginalPath::parse("opaque.bin", profile=Connected)
  guard inventory.open_file(path) is Some(reader) else { abort("file") }
  match reader.read_chunk() {
    Chunk(first, next) => {
      assert_eq(first.length(), 65536)
      assert_eq(next.position(), 65536UL)
      assert_eq(next.byte_length(), 65539UL)
      for i, byte in first {
        assert_eq(byte, (i % 256).to_byte())
      }
      match next.read_chunk() {
        Chunk(tail, end) => {
          assert_eq(tail, b"\x00\x01\x02")
          assert_eq(end.position(), 65539UL)
          assert_true(end.read_chunk() is EndOfFile)
        }
        EndOfFile => abort("tail must not be lost")
      }
    }
    EndOfFile => abort("file must not be treated as empty")
  }
}

///|
test "retained original reader distinguishes empty file directory and missing path" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([("empty.bin", b"")]),
    ["empty-dir"],
    NotReported,
  )
  let empty = @document.OriginalPath::parse("empty.bin", profile=Connected)
  let directory = @document.OriginalPath::parse("empty-dir", profile=Connected)
  let missing = @document.OriginalPath::parse("absent", profile=Connected)
  guard inventory.open_file(empty) is Some(reader) else {
    abort("empty file remains an actual retained file")
  }
  assert_eq(reader.byte_length(), 0UL)
  assert_eq(reader.position(), 0UL)
  assert_true(reader.read_chunk() is EndOfFile)
  assert_true(inventory.open_file(directory) is None)
  assert_true(inventory.open_file(missing) is None)
}
