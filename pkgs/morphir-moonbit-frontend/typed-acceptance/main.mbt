///|
fn main raise {
  let sources = [
    (
      "foundation", "pub fn choose(flag : Bool, a : Int32, b : Int) -> Int32 { let value : Int = if flag { a } else { b }; identity(value) }\nfn identity(value : Int32) -> Int { value }",
    ),
    (
      "strings", "// λ😀 literal offsets\nfn prefix() -> String { \"Hello, \" }\npub fn greet(name : String) -> String { let greeting : String = prefix(); greeting + name }\npub fn welcome(name : String, enabled : Bool) -> String { if enabled { greet(name) } else { \"\" } }\npub fn same(a : String, b : String) -> Bool { a == b }\npub fn escapes() -> String { \"\\u{1f600}\\u0301\\x41\\o101\\n\" }\npub fn ignore_text(s : String) -> Bool { true }\npub fn choose(a : String, b : String, flag : Bool) -> String { let value = if flag { a } else { b }; identity(value) }\nfn identity(s : String) -> String { s }",
    ),
    (
      "bounded", "pub fn join(a : String, b : String) -> String { a + b }\npub fn short() -> Bool { false && (join(\"abc\", \"def\") == \"\") }\npub fn ignore_text(s : String) -> Bool { true }\npub fn order() -> String { take(fail_growth(), fail_literal()) }\nfn take(a : String, b : String) -> String { a }\nfn fail_growth() -> String { \"abc\" + \"def\" }\nfn fail_literal() -> String { \"123456\" }",
    ),
  ]
  let models = []
  for (id, source) in sources {
    let input : @frontend.Input = {
      unit_id: id + ".mbt",
      package_name: "typed/acceptance/" + id,
      module_name: "main",
      source,
    }
    let output = if id == "foundation" {
      @frontend.compile_typed_library(input)
    } else {
      @frontend.compile_string_library(
        input,
        max_string_code_units=if id == "bounded" { 5 } else { 1048576 },
      )
    }
    let generated = @generator.generate({
      unit_id: output.unit_id,
      ir: output.ir,
      metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
      annotations: output.annotations,
      provenance: output.provenance,
    })
    let runtime = @scheme.Runtime::new()
    @backend.install(runtime, model_errors=true)
    ignore(runtime.eval(@backend.emit_file(output.ir)))
    fn entry(name : String) -> @ir.FQName {
      output.entries.filter(e => e.local_name.to_canonical() == name)[0]
    }
    if id == "foundation" {
      for flag in [false, true] {
        guard @backend.call_entry(runtime, entry("choose"), [
            @scheme.Boolean(flag),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("-2147483648"),
            ]),
            @scheme.Tagged("morphir/SDK:int#int32", [
              @scheme.integer("2147483647"),
            ]),
          ])
          is Tagged(_, [Number(Integer(n))]) else {
          fail("Int32 result")
        }
        assert_eq(
          n.to_string(),
          if flag {
            "-2147483648"
          } else {
            "2147483647"
          },
        )
      }
    } else if id == "strings" {
      assert_eq(
        @backend.call_entry(runtime, entry("greet"), [@scheme.Text("😀")]).as_text(),
        "Hello, 😀",
      )
      for enabled in [false, true] {
        assert_eq(
          @backend.call_entry(runtime, entry("welcome"), [
            @scheme.Text("Morphir"),
            @scheme.Boolean(enabled),
          ]).as_text(),
          if enabled {
            "Hello, Morphir"
          } else {
            ""
          },
        )
      }
      assert_eq(
        @backend.call_entry(runtime, entry("escapes"), []).as_text(),
        "😀́AA\n",
      )
      guard @backend.call_entry(runtime, entry("same"), [
          @scheme.Text("é"),
          @scheme.Text("é"),
        ])
        is Boolean(equal) else {
        fail("Bool result")
      }
      assert_false(equal)
    } else {
      assert_eq(
        @backend.call_entry(runtime, entry("join"), [
          @scheme.Text("a"),
          @scheme.Text("😀"),
        ]).as_text(),
        "a😀",
      )
      guard @backend.call_entry(runtime, entry("short"), []) is Boolean(value) else {
        fail("Bool result")
      }
      assert_false(value)
      for name in ["order"] {
        try {
          ignore(@backend.call_entry(runtime, entry(name), []))
          fail("Expected bound refusal")
        } catch {
          @scheme.Domain(code, _) => assert_eq(code, "sdk.out_of_range")
          error => raise error
        }
      }
    }
    models.push(
      (
        {
          "id": id,
          "source": source,
          "module": generated.project.module_name,
          "symbols": generated.symbols.map(s => {
            (
              {
                "fqname": s.fqname,
                "function": s.generated_name,
                "public": s.public,
              } : Json)
          }),
          "artifacts": generated.artifacts.map(a => {
            (
              {
                "path": a.path,
                "content": match a.content {
                  Text(text) => Json::string(text)
                  Binary(bytes) =>
                    Json::array(
                      bytes
                      .to_array()
                      .map(b => Json::number(b.to_int().to_double())),
                    )
                },
              } : Json)
          }),
          "sdkProfile": generated.project.dependencies[0].api_profile,
        } : Json),
    )
  }
  println(
    ({ "models": models, "parser": @frontend.PARSER_VERSION } : Json).stringify(),
  )
}
