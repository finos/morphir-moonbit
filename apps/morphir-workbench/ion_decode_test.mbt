///|
/// The base64 bytes of the generated `symbols.10n` of a MoonBit compile.
fn generated_symbols() -> String {
  let reply = @pipeline.execute({
    "operation": "compile",
    "source": "pub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }",
    "languageId": "moonbit",
    "target": "moonbit",
  })
  let found = match json_member(reply, "artifacts") {
    Array(files) =>
      files.filter(file => {
        json_member(file, "path") == Json::string("symbols.10n")
      })
    _ => []
  }
  match found {
    [file, ..] =>
      match json_member(file, "content") {
        String(content) => content
        _ => ""
      }
    [] => ""
  }
}

///|
fn decode(source : String) -> Json {
  @pipeline.execute({
    "operation": "decode-ion",
    "path": "symbols.10n",
    "source": source,
  })
}

///|
test "a generated binary Ion file decodes to Ion text that reads back to the same values" {
  let source = generated_symbols()
  let reply = decode(source)
  let text = match json_member(reply, "text") {
    String(text) => text
    _ => ""
  }
  @expect.expect_all(s => {
    s.expect(source, label="generated").not().to_be_empty()
    s
    .expect(reply, label="reply")
    .to_contain_json({ "success": true, "path": "symbols.10n" })
    s.expect(text, label="text").not().to_be_empty()
    // Round trip: the text reads back to values whose binary form decodes to the same text.
    let again = @ion_text.write_all_pretty(
      @ion_binary.read_binary(
        @ion_binary.write_binary(@ion_text.read_ion_datagram(text))[:],
      ),
    )
    s.expect(again, label="round trip").to_equal(text)
  })
}

///|
test "corrupt, non-Ion and oversized files fail with their codes" {
  // The version marker followed by a struct descriptor whose length runs past the end.
  let corrupt = @base64.encode(b"\xE0\x01\x00\xEA\xDE\x9F\x81"[:])
  let plain = @base64.encode(b"module A"[:])
  let large = "A".repeat((@pipeline.ion_input_limit + 2) / 3 * 4 + 4)
  let code = fn(reply : Json) { json_member(reply, "code") }
  @expect.expect_all(s => {
    s
    .expect(code(decode(corrupt)), label="corrupt")
    .to_satisfy(c => c is String(text) && text.has_prefix("ion."))
    s
    .expect(decode(corrupt), label="corrupt stage")
    .to_contain_json({ "success": false, "stage": "decode" })
    s
    .expect(code(decode(plain)), label="not Ion")
    .to_equal(Json::string("workbench.not_binary_ion"))
    s
    .expect(code(decode("%%%")), label="not base64")
    .to_equal(Json::string("workbench.invalid_encoding"))
    s
    .expect(code(decode(large)), label="too large")
    .to_equal(Json::string("workbench.ion_input_too_large"))
  })
}
