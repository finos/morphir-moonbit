///|
fn files(
  entries : Array[(String, String)],
  open_file~ : String? = None,
) -> @projects.Files raise {
  @projects.Files::new(Map::from_array(entries), open_file~)
}

///|
fn path(text : String) -> @discovery.ProjectPath raise {
  @discovery.ProjectPath::parse(text)
}

///|
fn legacy(language : String, name~ : String = "user") -> @project.Project raise {
  @project.Project::single(
    @ids.LanguageId::parse(language),
    @ids.SourcePackageName::parse(name),
    @ids.SourcePath::parse(
      "src/main." + (if language == "scheme" { "scm" } else { "mbt" }),
    ),
    "source " + language,
  )
}

///|
test "files drive project discovery and current project follows the innermost owning file" {
  let workspace = files([
    (
      "morphir.toml", "[workspace]\nmembers=['one','one/nested']\ndefault_member='one'\n[project]\nname='Root'\n",
    ),
    ("one/morphir.toml", "[project]\nname='Same'\n"),
    ("one/main.scm", "42"),
    ("one/nested/morphir.toml", "[project]\nname='Same'\n"),
    ("one/nested/main.scm", "43"),
    ("readme.md", "Workspace"),
  ])
  assert_eq(workspace.discover().projects.length(), 3)
  assert_eq(workspace.current(), Some(path("one")))
  assert_eq(
    workspace.open("one/nested/main.scm").current(),
    Some(path("one/nested")),
  )
  assert_eq(workspace.open("readme.md").current(), Some(path(".")))
  let edited = workspace.write(
    "one/morphir.toml", "[project]\nname='Renamed'\n[frontend]\nlanguage='moonbit'\n",
  )
  assert_eq(edited.discover().projects[1].name, "Renamed")
  assert_eq(
    edited.discover().projects[1].document.text("frontend.language", ""),
    "moonbit",
  )
  assert_eq(workspace.discover().projects[1].name, "Same")
  assert_eq(@projects.Files::from_json(edited.to_json()), edited)
}

///|
test "migration uses the recent project as root and keeps every source and draft" {
  let scheme = {
    ..legacy("scheme"),
    target: Some(@project.Generation::parse("elm").unwrap()),
  }
  let moonbit = legacy("moonbit")
  let migrated = @projects.migrate(
    [scheme, moonbit],
    "moonbit",
    intent=Some("Intent"),
    concept=Some("Concept"),
    worksheet=Some("(+ 1 2)"),
  )
  assert_eq(migrated.read("src/main.mbt"), Some("source moonbit"))
  assert_eq(
    migrated.read("packages/user-scheme/src/main.scm"),
    Some("source scheme"),
  )
  assert_eq(migrated.read("intent.md"), Some("Intent"))
  assert_eq(migrated.read("src/model.mfs"), Some("Concept"))
  assert_eq(migrated.read("worksheet.scm"), Some("(+ 1 2)"))
  assert_eq(migrated.current(), Some(path(".")))
  let migrated_member = migrated.discover().projects[1]
  assert_eq(migrated_member.document.text("pipeline.backend", ""), "elm")
  let distinct = @projects.migrate(
    [legacy("scheme", name="Quotes"), legacy("moonbit", name="Pricing")],
    "scheme",
  )
  assert_true(distinct.read("packages/Pricing/morphir.toml") is Some(_))
  let single = @projects.migrate([scheme], "scheme")
  assert_eq(single.discover().projects.length(), 1)
  assert_eq(single.discover().projects[0].root, "")
}

///|
test "an interrupted file save leaves the committed tree and legacy records intact" {
  let old = @projects.migrate([legacy("scheme")], "scheme")
  let updated = old
    .write("src/main.scm", "changed")
    .write("intent.md", "new intent")
  let store : Map[String, String] = Map::from_array([
    ("workspace.project.scheme.v1", "legacy copy"),
  ])
  let read = fn(key : String) { store.get(key) }
  let write = fn(key : String, value : String) {
    store[key] = value
    true
  }
  assert_true(old.save("workspace", "one", read, write))
  let count = Ref(0)
  assert_true(
    !updated.save("workspace", "two", read, fn(key, value) {
      count.val += 1
      if count.val == 2 {
        false
      } else {
        write(key, value)
      }
    }),
  )
  assert_eq(@projects.load("workspace", read), Some(old))
  assert_eq(store["workspace.project.scheme.v1"], "legacy copy")
  assert_true(!updated.save("workspace", "one", read, write))
  assert_eq(@projects.load("workspace", read), Some(old))
  assert_true(updated.save("workspace", "three", read, write))
  assert_eq(@projects.load("workspace", read), Some(updated))
  assert_true(
    !old.save("workspace", "four", read, fn(key, value) {
      if key == "workspace.tree.v1" {
        false
      } else {
        write(key, value)
      }
    }),
  )
  assert_eq(@projects.load("workspace", read), Some(updated))
}

///|
test "settings edit real project files and remove an override to reveal inherited values" {
  let workspace = files([
    (
      "morphir.toml", "[workspace]\nmembers=['member']\n[frontend]\nlanguage='scheme'\n",
    ),
    (
      "member/morphir.toml", "# Project\n[project]\nname = 'Member' # name\n\n[frontend] # local\nlanguage = 'moonbit' # language\n",
    ),
  ])
  let inherited = workspace.configure(path("member"), @projects.Language, None)
  assert_eq(
    inherited.setting(path("member"), @projects.Language).effective,
    Some("scheme"),
  )
  assert_eq(
    inherited.setting(path("member"), @projects.Language).override_value,
    None,
  )
  assert_eq(
    inherited.setting(path("member"), @projects.Language).origin,
    Some("morphir.toml"),
  )
  let overridden = inherited.configure(
    path("member"),
    @projects.Language,
    Some("elm"),
  )
  assert_eq(
    overridden.setting(path("member"), @projects.Language).effective,
    Some("elm"),
  )
  assert_eq(
    overridden.setting(path("member"), @projects.Language).override_value,
    Some("elm"),
  )
  assert_true(
    overridden
    .read("member/morphir.toml")
    .unwrap()
    .has_prefix(
      "# Project\n[project]\nname = 'Member' # name\n\n[frontend] # local\n",
    ),
  )
  let generated = overridden.configure(
    path("member"),
    @projects.Generation,
    Some("moonbit"),
  )
  assert_eq(
    generated.setting(path("member"), @projects.Generation).effective,
    Some("moonbit"),
  )
  let shared = generated.configure_workspace(
    @projects.SourceProfile,
    Some("library"),
  )
  assert_eq(
    shared.setting(path("member"), @projects.SourceProfile).effective,
    Some("library"),
  )
}

///|
test "legacy conversion is explicit and preserves the original manifest" {
  let manifest = "{\"name\":\"Orders\",\"sourceDirectory\":\"lib\",\"exposedModules\":[\"Api\"]}\n"
  let workspace = files([
    ("morphir.json", manifest),
    ("lib/Orders/Api.elm", "module Orders.Api exposing (value)\nvalue = 1"),
  ])
  assert_true(
    try {
      ignore(workspace.configure(path("."), @projects.Generation, Some("elm")))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    workspace.setting(path("."), @projects.Language).effective,
    Some("elm"),
  )
  let converted = workspace.convert_legacy(path("."))
  assert_eq(converted.read("morphir.json"), Some(manifest))
  assert_eq(
    converted.discover().projects[0].document.text(
      "project.source_directory", "",
    ),
    "lib",
  )
  let edited = converted.configure(path("."), @projects.Generation, Some("elm"))
  assert_eq(
    edited.setting(path("."), @projects.Generation).effective,
    Some("elm"),
  )
}

///|
test "project settings retain dotted configuration instead of adding conflicting headers" {
  let source = "# keep\nproject.name='Shop'\nfrontend.language='scheme' # language\npipeline.backend='scheme'\n"
  let files = @projects.Files::new(
    Map([("morphir.toml", source), ("src/main.scm", "1")]),
  )
  let root = @discovery.ProjectPath::parse(".")
  let changed = files.configure(root, @projects.Language, Some("elm"))
  assert_eq(
    changed.read("morphir.toml"),
    Some(source.replace(old="'scheme' # language", new="\"elm\" # language")),
  )
  let added = files.configure(root, @projects.SourceProfile, Some("stable"))
  assert_eq(
    added.read("morphir.toml"),
    Some(source + "frontend.profile = \"stable\"\n"),
  )
}
