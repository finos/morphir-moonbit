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
    // Round trip: the text reads back to the values of the original binary.
    let original = @ion_binary.read_binary(@base64.decode(source[:])[:])
    let read_back = @ion_text.read_ion_datagram(text[:])
    s
    .expect(
      read_back.length() == original.length() &&
      original.mapi((i, value) => value.equals(read_back[i])).all(same => same),
      label="round trip",
    )
    .to_be_true()
    s
    .expect(json_member(reply, "values"), label="values")
    .to_equal(Json::number(original.length().to_double()))
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

///|
/// The base64 of the binary form of Ion `text`.
fn binary_of(text : String) -> String raise {
  @base64.encode(
    @ion_binary.write_binary(@ion_text.read_ion_datagram(text[:]))[:],
  )
}

///|
fn code_of(reply : Json) -> Json {
  json_member(reply, "code")
}

///|
test "the budgeted writer writes what write_all_pretty writes" {
  let texts = [
    "a::b::{name: \"x\", list: [1, 2.5e0, 3.25, null.int, true], empty: {}, none: []}",
    "(f 'quoted symbol' [] () + -) 2024-01-02T03:04:05Z {{ aGVsbG8= }} {{ \"clob\" }}",
    "$ion_symbol_table::{symbols: [\"one\", \"two\"]} $10 $11 'one'::[[[1]], {a: (b c)}]",
    "\"line\\nbreak \\u00e9\" nan +inf -0e0 1.0d2",
  ]
  let symbols = @ion_binary.read_binary(
    @base64.decode(generated_symbols()[:])[:],
  )
  @expect.expect_all(s => {
    for text in texts {
      let values = @ion_text.read_ion_datagram(text[:])
      s
      .expect(
        @pipeline.ion_text_within(values, @pipeline.ion_text_limit) ==
        Written(@ion_text.write_all_pretty(values)),
        label=text,
      )
      .to_be_true()
    }
    s
    .expect(
      @pipeline.ion_text_within(symbols, @pipeline.ion_text_limit) ==
      Written(@ion_text.write_all_pretty(symbols)),
      label="symbols.10n",
    )
    .to_be_true()
  })
}

///|
test "the text budget stops the writer before it passes the limit" {
  let values = @ion_text.read_ion_datagram(
    ("[".repeat(20) + "0,".repeat(1000) + "]".repeat(20))[:],
  )
  @expect.expect_all(s => {
    for limit in [0, 1, 100, 5000] {
      let stopped = @pipeline.ion_text_within(values, limit) is OverBudget(used) &&
        used <= limit
      s.expect(stopped, label="limit " + limit.to_string()).to_be_true()
    }
  })
}

///|
test "a small file whose text passes the limit is refused" {
  // About 100 KB of binary: 99,000 zeros 30 lists deep. Each prints on a line of 63 characters, over 6 Mi in all.
  let source = binary_of("[".repeat(30) + "0,".repeat(99000) + "]".repeat(30))
  @expect.expect_all(s => {
    s.expect(source.length(), label="small input").to_be_less_than(200 * 1024)
    s
    .expect(decode(source), label="reply")
    .to_contain_json({
      "success": false,
      "code": "workbench.ion_text_too_large",
      "stage": "decode",
    })
  })
}

///|
test "a file too deep or with too many values is refused before it is read" {
  let deep = binary_of("[".repeat(130) + "]".repeat(130))
  let deepest_allowed = binary_of("[".repeat(129) + "]".repeat(129))
  let many = binary_of("[" + "0,".repeat(100000) + "]")
  let annotated = binary_of("a::" + "[".repeat(129) + "]".repeat(129))
  @expect.expect_all(s => {
    s
    .expect(code_of(decode(deep)), label="deep")
    .to_equal(Json::string("workbench.ion_too_deep"))
    s
    .expect(decode(deepest_allowed), label="128 levels")
    .to_contain_json({ "success": true })
    s
    .expect(code_of(decode(annotated)), label="an annotation adds no level")
    .to_equal(Json::null())
    s
    .expect(code_of(decode(many)), label="many")
    .to_equal(Json::string("workbench.ion_too_many_values"))
  })
}

///|
test "every prefix of a real file gives a code or its values, never an abort" {
  let bytes = @base64.decode(generated_symbols()[:])
  @expect.expect_all(s => {
    for length in 0..<=bytes.length() {
      let reply = decode(@base64.encode(bytes[0:length]))
      let label = "prefix " + length.to_string()
      if json_member(reply, "success") != Json::boolean(true) {
        s
        .expect(code_of(reply), label~)
        .to_satisfy(code => code is String(text) && text != "")
      }
    }
    for length in 0..<4 {
      s
      .expect(
        code_of(decode(@base64.encode(bytes[0:length]))),
        label="marker prefix " + length.to_string(),
      )
      .to_equal(Json::string("workbench.not_binary_ion"))
    }
  })
}

///|
/// Property: random bytes after the version marker give a code or values, never an abort.
test "random bytes after the version marker never abort the decode" {
  @expect.for_all((octets : Array[UInt32]) => {
    let bytes = Bytes::from_array(
      [
        b'\xE0',
        b'\x01',
        b'\x00',
        b'\xEA',
        ..octets.map(o => (o % 256).to_byte()),
      ],
    )
    let reply = decode(@base64.encode(bytes[:]))
    if json_member(reply, "success") != Json::boolean(true) {
      @expect.expect(code_of(reply), label=reply.stringify()).to_satisfy(code => {
        code is String(text) && text != ""
      })
    }
  })
}
