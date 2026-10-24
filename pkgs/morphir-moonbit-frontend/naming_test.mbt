///|
test "normalization collisions warn and recover without merging source functions" {
  let first = "pub fn is_ready() -> Bool { true }"
  let second = "pub fn isReady() -> Bool { false }"
  let call = "pub fn decide() -> Bool { is_ready() != isReady() }"
  let output = @frontend.compile_library(
    input(first + "\n" + second + "\n" + call),
  )
  assert_eq(output.entries.map(e => e.local_name.to_canonical()), [
    "decide", "is-ready", "is-ready-source-69735265",
  ])
  assert_eq(output.warnings.length(), 1)
  let warning = output.warnings[0]
  assert_eq(warning.code, "moonbit_frontend.name_normalization_collision")
  assert_eq(warning.locations.map(l => l.original), ["isReady", "is_ready"])
  assert_eq(warning.locations.map(l => l.source.unwrap().start_line), [2, 1])
  assert_eq(warning.locations[0].source.unwrap().start_column, 7)
  assert_true(warning.fix.contains("Rename is_ready to is_ready_renamed_1"))
  for (entry, expected) in output.entries.zip([true, true, false]) {
    assert_eq(library_result(output, entry, []), expected)
  }
  let reversed = @frontend.compile_library(
    input(second + "\n" + call + "\n" + first),
  )
  assert_eq(output.entries, reversed.entries)
  assert_eq(
    warning.locations.map(l => l.allocated),
    reversed.warnings[0].locations.map(l => l.allocated),
  )
  ignore(library_generated(output))
}

///|
test "collision escapes reserve authored suffixes and fixes avoid occupied names" {
  let source = "pub fn is_ready() -> Bool { true }\n" +
    "pub fn isReady() -> Bool { false }\n" +
    "pub fn is_ready_source_69735265() -> Bool { true }\n" +
    "pub fn is_ready_renamed_1() -> Bool { false }"
  let output = @frontend.compile_library(input(source))
  assert_true(
    output.entries.any(e => {
      e.local_name.to_canonical() == "is-ready-source-6973526561"
    }),
  )
  assert_true(output.warnings[0].fix.contains("is_ready_renamed_2"))
  assert_eq(output.entries.length(), 4)
  ignore(library_generated(output))
}

///|
test "word and initialism identities stay distinct and ordinary names stay quiet" {
  let output = @frontend.compile_library(
    input(
      "pub fn readHTTP() -> Bool { true }\npub fn readHttp() -> Bool { false }\npub fn isREADY() -> Bool { true }",
    ),
  )
  assert_eq(output.entries.map(e => e.local_name.to_canonical()), [
    "is-READY", "read-HTTP", "read-http",
  ])
  assert_true(output.warnings.is_empty())
  let plain = @frontend.compile(
    input("pub fn eligible(is_ready : Bool) -> Bool { is_ready }"),
  )
  assert_eq(plain.entry.local_name.to_canonical(), "eligible")
  assert_true(plain.warnings.is_empty())
}

///|
test "parameter collision recovery and generated-looking bindings cannot capture values" {
  let output = @frontend.compile_library(
    input(
      "pub fn f(ready : Bool, ready_shadow_1 : Bool, ready_equality_left_1 : Bool) -> Bool { let ready = !ready; let ready = !ready; (ready == ready_shadow_1) != ready_equality_left_1 }",
    ),
  )
  assert_true(output.warnings.is_empty())
  for a in [false, true] {
    for b in [false, true] {
      for c in [false, true] {
        assert_eq(
          library_result(output, output.entries[0], [a, b, c]),
          (a == b) != c,
        )
      }
    }
  }
  ignore(library_generated(output))
  let collision = @frontend.compile(
    input(
      "pub fn f(is_ready : Bool, isReady : Bool) -> Bool { is_ready != isReady }",
    ),
  )
  assert_eq(collision.warnings.length(), 1)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(@backend.emit_file(collision.ir)))
  assert_true(
    @backend.call_entry(runtime, collision.entry, [
      @scheme.Boolean(true),
      @scheme.Boolean(false),
    ])
    is Boolean(true),
  )
}

///|
test "strict naming fails rather than returning warning-bearing output" {
  assert_true(
    try {
      ignore(
        @frontend.compile_library(
          input(
            "pub fn is_ready() -> Bool { true }\npub fn isReady() -> Bool { false }",
          ),
          strict_naming=true,
        ),
      )
      false
    } catch {
      @frontend.Invalid(d) =>
        d.code == "moonbit_frontend.name_normalization_collision" &&
        d.detail.contains("fix:")
      error => raise error
    },
  )
  assert_true(
    try {
      ignore(
        @frontend.compile(
          input(
            "pub fn f(is_ready : Bool, isReady : Bool) -> Bool { is_ready }",
          ),
          strict_naming=true,
        ),
      )
      false
    } catch {
      @frontend.Invalid(d) =>
        d.code == "moonbit_frontend.name_normalization_collision"
      error => raise error
    },
  )
}

///|
test "lexical errors cannot silently truncate original names" {
  for
    source in [
      "pub fn readyλ() -> Bool { true }", "pub fn readyμ() -> Bool { true }", "pub fn f(readyλ : Bool) -> Bool { readyλ }",
    ] {
    assert_eq(failure(source).code, "moonbit_frontend.syntax")
    assert_eq(library_failure(source).code, "moonbit_frontend.syntax")
    assert_true(failure(source).detail.contains("Lexing error"))
    assert_true(failure(source).source is Some(_))
  }
}
