///|
fn main raise {
  let registry = @data.Registry::new()
  let unit = @data.IRUnit::new("model", @fixtures.conformance())
  let text = match registry.encode("ion-text", unit) {
    Text(text) => text
    Binary(_) => abort("Expected text")
  }
  let bytes = match registry.encode("ion-binary", unit) {
    Binary(bytes) => bytes
    Text(_) => abort("Expected bytes")
  }
  println(
    (
      { "ionText": text, "ionBinary": bytes.to_array().map(b => b.to_int()) } :
      Json).stringify(),
  )
}
