///|
test "TOML semantic round trip retains unknown values" {
  let text = "title = 'demo'\n[project]\nname = 'Core'\n[extension]\nlarge = 9223372036854775807\ndate = 2026-09-28T12:30:00Z\nvalues = [1, 2, 3]\n"
  let first = @config.parse(text)
  let second = @config.parse(first.encode())
  assert_true(first.value == second.value)
}

///|
test "merge replaces arrays and secrets, preserving winning provenance" {
  let base = @config.parse(
    "[project]\nname='Base'\nexposed_modules=['A','B']\n[credentials]\nkey={env='FIRST'}",
    origin="base",
  )
  let overlay = @config.parse(
    "[project]\nexposed_modules=['C']\n[credentials]\nkey={file='secret'}",
    origin="user",
  )
  let result = @config.merge(base, overlay)
  assert_eq(result.text("project.name", ""), "Base")
  assert_eq(result.strings("project.exposed_modules"), ["C"])
  assert_eq(result.provenance.get("project.name"), Some("base"))
  assert_eq(result.provenance.get("project.exposed_modules"), Some("user"))
  assert_true(result.get("credentials.key.env") is None)
  assert_true(base.get("credentials.key.env") is Some(_))
}

///|
test "environment preserves underscores and shorter paths win" {
  let result = @config.environment(
    Map::from_array([
      ("MORPHIR_PROJECT__SOURCE_DIRECTORY", "lib"),
      ("MORPHIR_PROJECT__NAME", "Overridden"),
      ("MORPHIR_PROJECT", "{\"name\":\"Short\"}"),
      ("MORPHIR_WORKSPACE__MEMBERS", "[\"a\",\"b\"]"),
      ("MORPHIR_HOME", "/unused"),
    ]),
  )
  assert_eq(result.text("project.name", ""), "Short")
  // Deep merge retains other keys when the shorter value is a table.
  assert_eq(result.text("project.source_directory", ""), "lib")
  assert_eq(result.strings("workspace.members"), ["a", "b"])
  assert_true(result.get("home") is None)
}

///|
test "environment conversions follow upstream mapping" {
  let result = @config.environment(
    Map::from_array([
      ("MORPHIR__IR__STRICT_MODE", "TRUE"),
      ("MORPHIR_IR__FORMAT_VERSION", "+003"),
      ("MORPHIR_CUSTOM__FLOAT", "1.5"),
      ("MORPHIR_CUSTOM__QUOTED", "\"text\""),
    ]),
  )
  assert_eq(result.get("ir.strict_mode"), Some(@toml.TomlBoolean(true)))
  assert_eq(result.get("ir.format_version"), Some(@toml.TomlInteger(3)))
  assert_eq(result.text("custom.float", ""), "1.5")
  assert_eq(result.text("custom.quoted", ""), "\"text\"")
}
