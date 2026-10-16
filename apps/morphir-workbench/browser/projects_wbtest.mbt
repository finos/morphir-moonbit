///|
fn catalog_fixture() -> Json {
  {
    "frontends": [
      {
        "languageId": "elm",
        "displayName": "Elm",
        "fileExtensions": [".elm"],
        "providerId": "morphir-elm",
        "defaultProfile": "library",
        "profiles": [{ "id": "library", "compileKind": "whole-project" }],
      },
      {
        "languageId": "moonbit",
        "displayName": "MoonBit",
        "fileExtensions": [".mbt"],
        "providerId": "morphir-moonbit",
        "defaultProfile": "moonbit-model-bool-v1",
        "profiles": [
          { "id": "moonbit-model-bool-v1", "compileKind": "each-file" },
          { "id": "moonbit-model-bool-library-v1", "compileKind": "each-file" },
        ],
      },
      {
        "languageId": "scheme",
        "displayName": "Scheme",
        "fileExtensions": [".scm"],
        "providerId": "morphir-scheme",
        "profiles": [],
      },
    ],
  }
}

///|
test "each language keeps its own project across language switches" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "scheme",
  }
  let (edited, _) = update(
    model,
    Source("(define kept 1)"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  let (elm, _) = update(edited, Language("elm"), @cmd.Emit(fn(_) { @cmd.none }))
  let (back, _) = update(
    elm,
    Language("scheme"),
    @cmd.Emit(fn(_) { @cmd.none }),
  )
  @expect.expect_all(s => {
    s
    .expect(active_text(elm), label="elm default")
    .to_contain("module Workbench.Main")
    s
    .expect(active_project(elm).active.to_string(), label="elm file")
    .to_equal("src/Workbench/Main.elm")
    s.expect(active_text(back), label="scheme kept").to_equal("(define kept 1)")
  })
}

///|
fn member_of(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
test "the offline request carries the project; connected mode carries source" {
  let model = {
    ..scope_model(),
    catalog: catalog_fixture(),
    language: "elm",
    connected: false,
  }
  let offline = compile_request(model, "compile")
  let connected = compile_request({ ..model, connected: true, }, "compile")
  @expect.expect_all(s => {
    s
    .expect(offline, label="offline")
    .to_contain_json({
      "operation": "compile",
      "project": {
        "name": "Workbench",
        "languageId": "elm",
        "exposedModules": ["Main"],
      },
    })
    s.expect(member_of(offline, "source"), label="no source").to_be_none()
    s
    .expect(connected, label="connected")
    .to_contain_json({ "operation": "compile", "languageId": "elm" })
    s.expect(member_of(connected, "source"), label="source").to_be_some()
  })
}

///|
test "file rules follow the selected profile and the defaults follow the language" {
  let model = { ..scope_model(), catalog: catalog_fixture(), }
  let elm = file_rules(model, "elm")
  let moonbit = file_rules(model, "moonbit")
  let library = with_selection(
    model, "moonbit", "moonbit-model-bool-library-v1",
  )
  @expect.expect_all(s => {
    s.expect(elm.layout, label="elm layout").to_equal(ManyFiles)
    s
    .expect(elm.extensions.map(e => e.to_string()), label="elm extensions")
    .to_equal([".elm"])
    s.expect(moonbit.layout, label="moonbit layout").to_equal(OneFile)
    s
    .expect(
      default_project(model, "moonbit").active.to_string(),
      label="moonbit file",
    )
    .to_equal("src/main.mbt")
    s
    .expect(
      default_project(library, "moonbit").active_file().content,
      label="library example",
    )
    .to_contain("fn gate")
    s
    .expect(
      default_project(model, "scheme").active.to_string(),
      label="scheme file",
    )
    .to_equal("src/main.scm")
  })
}
