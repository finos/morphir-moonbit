///|
fn path(text : String) -> @ids.SourcePath {
  @ids.SourcePath::parse(text) catch {
    _ => abort(text)
  }
}

///|
fn elm_rules() -> @project.FileRules {
  {
    extensions: [@ids.FileExtension::parse(".elm") catch { _ => abort("ext") }],
    layout: ManyFiles,
  }
}

///|
fn moonbit_rules() -> @project.FileRules {
  {
    extensions: [@ids.FileExtension::parse(".mbt") catch { _ => abort("ext") }],
    layout: OneFile,
  }
}

///|
fn shop() -> @project.Project {
  @project.Project::single(
    @ids.LanguageId::parse("elm") catch {
      _ => abort("lang")
    },
    @ids.SourcePackageName::parse("Shop.Orders") catch {
      _ => abort("name")
    },
    path("src/Shop/Orders/Api.elm"),
    "module Shop.Orders.Api exposing (..)\n",
    exposed=[@ids.SourceModuleName::parse("Api") catch { _ => abort("module") }],
  )
}

///|
fn error_code(f : () -> @project.Project raise @project.ProjectError) -> String {
  try {
    ignore(f())
    ""
  } catch {
    @project.ProjectError(code, _) => code
  }
}

///|
test "adding an Elm file makes it active and gives it a module header" {
  let project = shop().add_file(elm_rules(), "src/Shop/Orders/Util.elm")
  @expect.expect_all(s => {
    s
    .expect(project.files.map(f => f.path.to_string()), label="files")
    .to_equal(["src/Shop/Orders/Api.elm", "src/Shop/Orders/Util.elm"])
    s
    .expect(project.active.to_string(), label="active")
    .to_equal("src/Shop/Orders/Util.elm")
    s
    .expect(project.active_file().content, label="header")
    .to_start_with("module Shop.Orders.Util exposing (..)")
    s
    .expect(project.modules().map(m => (m.0.to_string(), m.1)), label="modules")
    .to_equal([("Api", true), ("Util", false)])
  })
}

///|
test "bad paths, duplicates, wrong extensions and one-file languages are refused" {
  @expect.expect_all(s => {
    s
    .expect(
      error_code(() => shop().add_file(elm_rules(), "../x.elm")),
      label="escape",
    )
    .to_equal("workbench.invalid_path")
    s
    .expect(
      error_code(() => shop().add_file(elm_rules(), "lib/X.elm")),
      label="outside src",
    )
    .to_equal("workbench.outside_source")
    s
    .expect(
      error_code(() => shop().add_file(elm_rules(), "src/Shop/Orders/Api.elm")),
      label="duplicate",
    )
    .to_equal("workbench.duplicate_path")
    s
    .expect(
      error_code(() => shop().add_file(elm_rules(), "src/Shop/Orders/Api.scm")),
      label="extension",
    )
    .to_equal("workbench.wrong_extension")
    s
    .expect(
      error_code(() => shop().add_file(moonbit_rules(), "src/other.mbt")),
      label="one file",
    )
    .to_equal("workbench.one_file_language")
    s
    .expect(
      error_code(() => shop().delete_file(path("src/Shop/Orders/Api.elm"))),
      label="last file",
    )
    .to_equal("workbench.last_file")
    s
    .expect(moonbit_rules().add_reason().unwrap_or(""), label="reason")
    .to_contain("morphir-ukvn.5.22.14")
    s.expect(elm_rules().add_reason(), label="no reason").to_be_none()
  })
}

///|
test "rename moves the active file and its exposure; delete drops the exposure" {
  let renamed = shop()
    .add_file(elm_rules(), "src/Shop/Orders/Util.elm")
    .rename_file(
      elm_rules(),
      path("src/Shop/Orders/Api.elm"),
      "src/Shop/Orders/Public.elm",
    )
  let deleted = renamed
    .set_active(path("src/Shop/Orders/Public.elm"))
    .delete_file(path("src/Shop/Orders/Public.elm"))
  @expect.expect_all(s => {
    s
    .expect(renamed.exposed.map(m => m.to_string()), label="exposure follows")
    .to_equal(["Public"])
    s
    .expect(renamed.files.map(f => f.content), label="content kept")
    .to_contain_element("module Shop.Orders.Api exposing (..)\n")
    s.expect(deleted.exposed, label="exposure dropped").to_be_empty()
    s
    .expect(deleted.active.to_string(), label="active moves")
    .to_equal("src/Shop/Orders/Util.elm")
  })
}

///|
test "the package name accepts only safe characters" {
  @expect.expect_all(s => {
    s
    .expect(shop().set_name("Shop.Billing").name.to_string(), label="ok")
    .to_equal("Shop.Billing")
    s
    .expect(error_code(() => shop().set_name("a\"b")), label="quote")
    .to_equal("workbench.invalid_package")
    s
    .expect(error_code(() => shop().set_name("")), label="empty")
    .to_equal("workbench.invalid_package")
  })
}

///|
/// Property: any script of edits keeps the project consistent: files is non-empty, paths are unique, the active
/// file exists, and every exposed module names a file's module.
test "edits never break the project invariants" {
  @expect.for_all((script : Array[(UInt32, UInt32)]) => {
    let mut project = shop()
    for step in script {
      let (op, n) = step
      let index = (n % project.files.length().reinterpret_as_uint()).reinterpret_as_int()
      let target = project.files[index].path
      let next = try {
        match op % 6 {
          0 => project.add_file(elm_rules(), "src/Shop/Orders/M\{n % 7}.elm")
          1 =>
            project.rename_file(
              elm_rules(),
              target,
              "src/Shop/Orders/R\{n % 7}.elm",
            )
          2 => project.delete_file(target)
          3 => project.set_active(target)
          5 =>
            project.set_name(
              match n % 3 {
                0 => "Shop.Orders"
                1 => "Shop"
                _ => "Other.Pkg"
              },
            )
          _ => {
            let full = @project.module_of(target).unwrap_or("Api")
            let last = full
              .split(".")
              .map(StringView::to_owned)
              .collect()
              .last()
              .unwrap_or("Api")
            let module_name = @ids.SourceModuleName::parse(last) catch {
              _ => abort("module")
            }
            project.set_exposed(module_name, n % 2 == 0)
          }
        }
      } catch {
        @project.ProjectError(_, _) => project
      }
      project = next
    }
    let paths = project.files.map(f => f.path.to_string())
    let modules = project.modules().map(m => m.0)
    @expect.expect_all(s => {
      s.expect(paths, label="files").not().to_be_empty()
      s.expect(paths, label="unique").to_have_no_duplicates()
      s
      .expect(paths, label="active")
      .to_contain_element(project.active.to_string())
      s
      .expect(project.exposed, label="exposed")
      .to_all_satisfy(e => modules.contains(e))
    })
  })
}

///|
test "set_name keeps a file's exposure under the new package name" {
  let project = shop().set_name("Shop")
  @expect.expect_all(s => {
    s
    .expect(project.exposed.map(m => m.to_string()), label="exposed")
    .to_equal(["Orders.Api"])
    s
    .expect(project.modules().map(m => (m.0.to_string(), m.1)), label="modules")
    .to_equal([("Orders.Api", true)])
  })
}

///|
test "renaming to an unparsable module drops the exposure" {
  let project = shop()
    .add_file(elm_rules(), "src/Shop/Orders/Util.elm")
    .rename_file(
      elm_rules(),
      path("src/Shop/Orders/Api.elm"),
      "src/Shop/Orders/a b.elm",
    )
  @expect.expect_all(s => {
    s.expect(project.exposed, label="exposed").to_be_empty()
    s
    .expect(project.modules().map(m => m.0.to_string()), label="modules")
    .to_equal(["Util"])
  })
}

///|
test "exposing a module that no file has is ignored" {
  let ghost = @ids.SourceModuleName::parse("Ghost") catch {
    _ => abort("ghost")
  }
  @expect.expect_all(s => {
    s
    .expect(shop().set_exposed(ghost, true) == shop(), label="unchanged")
    .to_be_true()
  })
}
