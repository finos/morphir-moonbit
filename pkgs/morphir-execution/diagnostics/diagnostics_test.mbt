///|
test "structured warnings round trip through Ion text and binary" {
  let warning : @diagnostics.Warning = {
    code: "frontend.name_collision",
    stage: "frontend",
    message: "Continue with allocated names",
    fix: "Rename one declaration",
    locations: [
      {
        owner: "value:example:main#is-ready",
        original: "is_ready",
        allocated: "is-ready",
        source: Some({
          start_line: 2,
          start_column: 7,
          end_line: 2,
          end_column: 15,
        }),
      },
      {
        owner: "value:example:main#is-ready-source-69735265",
        original: "isReady",
        allocated: "is-ready-source-69735265",
        source: None,
      },
    ],
  }
  let ion = warning.to_ion()
  assert_eq(
    @diagnostics.warning_from_ion(
      @ion_text.read_ion(@ion_text.write_ion(ion)[:]),
    ),
    Some(warning),
  )
  assert_eq(
    @diagnostics.warning_from_ion(
      @ion_binary.read_binary_value(@ion_binary.write_binary_value(ion)[:]),
    ),
    Some(warning),
  )
  assert_eq(
    @diagnostics.warning_from_ion(@ion_text.read_ion("unknown::{x:1}")),
    None,
  )
  assert_true(warning.display().contains("fix: Rename"))
}

///|
test "marked malformed diagnostic records cannot silently disappear" {
  for
    input in [
      "morphir_warning::{contract:\"morphir-warning-v1\"}", "morphir_warning::{contract:\"morphir-warning-v1\",severity:\"warning\",code:\"x\",stage:\"frontend\",message:\"x\",fix:\"x\",locations:[{owner:\"x\",original:\"x\",allocated:\"x\",source:{start_line:3,start_column:1,end_line:2,end_column:1}}]}",
      "morphir_warning::{contract:\"morphir-warning-v1\",severity:\"warning\",code:\"x\",code:\"y\",stage:\"frontend\",message:\"x\",fix:\"x\",locations:[]}",
    ] {
    assert_true(
      try {
        ignore(@diagnostics.warning_from_ion(@ion_text.read_ion(input[:])))
        false
      } catch {
        @diagnostics.InvalidDiagnostic(_) => true
        error => raise error
      },
    )
  }
}
