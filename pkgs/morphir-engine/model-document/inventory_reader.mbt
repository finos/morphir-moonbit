///|
/// Immutable cursor into one file in the inventory's defensive storage. Its
/// private position can only advance through bounded reads. Holding this view
/// retains bytes, not opening currentness, source authority or download rights.
pub struct OriginalFileReader {
  priv bytes : Bytes
  priv offset : Int32
}

///|
/// Each Chunk owns a defensive copy of at most 64 KiB. EndOfFile is separate
/// from a missing path and also represents a genuinely retained empty file.
pub(all) enum OriginalFileRead {
  EndOfFile
  Chunk(Bytes, OriginalFileReader)
}

///|
/// Select the SAME private file backing without copying its contents. Callers
/// must preflight and fund their own reads and encodings before copying bytes.
pub fn OriginalInventory::open_file(
  self : OriginalInventory,
  path : OriginalPath,
) -> OriginalFileReader? {
  self.storage.files.get(path.to_string()).map(bytes => { bytes, offset: 0, })
}

///|
pub fn OriginalFileReader::byte_length(self : OriginalFileReader) -> UInt64 {
  self.bytes.length().to_uint64()
}

///|
pub fn OriginalFileReader::position(self : OriginalFileReader) -> UInt64 {
  self.offset.to_uint64()
}

///|
/// A pure transition. The returned cursor retains the SAME immutable backing;
/// neither reading nor changing a foreign chunk can mutate another view.
pub fn OriginalFileReader::read_chunk(
  self : OriginalFileReader,
) -> OriginalFileRead {
  let remaining = self.bytes.length() - self.offset
  if remaining == 0 {
    return EndOfFile
  }
  let length = if remaining > 65536 { 65536 } else { remaining }
  let owned = FixedArray::make(length, (0 : Byte))
  owned.blit_from_bytes(0, self.bytes, self.offset, length)
  // The fresh array has no other owner and is never mutated after this handoff.
  Chunk(owned.unsafe_reinterpret_as_bytes(), {
    bytes: self.bytes,
    offset: self.offset + length,
  })
}
