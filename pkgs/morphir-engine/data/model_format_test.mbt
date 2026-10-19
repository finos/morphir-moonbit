///|
test "model format is closed and YAML shares typed JSON semantics" {
  assert_eq(@data.ModelFormat::from_control("yaml"), @data.ModelFormat::YAML)
  assert_eq(@data.ModelFormat::infer_path("MODEL.YML"), Some(@data.ModelFormat::YAML))
  assert_eq(@data.ModelFormat::infer_path("model.txt"), None)
  let source = b"\xef\xbb\xbf# preserve\r\nformatVersion: 4\r\ndistribution: {Library: {packageName: parity, dependencies: {}, def: {modules: {}}}}\r\n"
  let unit = @data.decode_model(@data.ModelFormat::YAML, source, unit_id="chosen")
  assert_eq(unit.id, "chosen")
  let expected = @data.Registry::new().decode("morphir-json", {
    unit_id: "chosen",
    content: Text("{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"parity\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"),
  })
  assert_eq(unit.distribution, expected.distribution)
  for codec in ["ion-text", "ion-binary"] {
    let registry = @data.Registry::new()
    assert_eq(registry.open_checkpoint(codec, registry.encode(codec, unit)).distribution, expected.distribution)
  }
  assert_eq(source, b"\xef\xbb\xbf# preserve\r\nformatVersion: 4\r\ndistribution: {Library: {packageName: parity, dependencies: {}, def: {modules: {}}}}\r\n")
}

///|
test "model bytes refuse invalid UTF8 and source budget before decoding" {
  let invalid = try { ignore(@data.decode_model(@data.ModelFormat::YAML, b"\xff")); "accepted" } catch { @data.Invalid(code, _) => code }
  assert_eq(invalid, "data.invalid_utf8")
  let oversized = try { ignore(@data.decode_model(@data.ModelFormat::YAML, b"12345", limits={ max_bytes: 4, max_depth: 128, max_values: 100000 })); "accepted" } catch { @data.Invalid(code, _) => code }
  assert_eq(oversized, "data.byte_limit")
}
