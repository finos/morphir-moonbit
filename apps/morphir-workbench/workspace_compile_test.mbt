///|
fn workspace_request(entries : Array[(String, String)]) -> Json {
  {
    "operation": "compile-workspace",
    "workspace": {
      "version": 1,
      "files": Json::object(
        Map::from_array(entries).map(fn(_, text) { Json::string(text) }),
      ),
      "openFile": Json::null(),
    },
    // Old UI selections have no authority over configuration files.
    "target": "unsupported-target",
    "languageId": "unsupported-language",
  }
}

///|
test "workspace compilation uses real per-project configs and preserves results alongside a failed project" {
  let reply = @pipeline.execute(
    workspace_request([
      (
        "morphir.toml", "[workspace]\nmembers=['one','two']\n[pipeline]\nbackend='scheme'\n",
      ),
      ("one/morphir.toml", "[project]\nname='One'\n"),
      ("one/src/main.scm", "42"),
      ("two/morphir.toml", "[project]\nname='Two'\n"),
      ("two/src/main.scm", "("),
    ]),
  )
  @expect.expect_all(s => {
    let result = s.expect(reply)
    result.at("success").to_equal(false)
    result.at("browserBuildPolicy").to_equal("source-only")
    result.at("projects[0].path").to_equal("one")
    result.at("projects[0].result.success").to_equal(true)
    result.at("projects[1].result.success").to_equal(false)
    result.at("projects[0].result.package").to_equal("one")
    result.at("artifacts[0].projectPath").to_equal("one")
    result.at("projects[0].target").to_equal("scheme")
  })
}

///|
test "workspace compile honors default member and explicit project and handles an empty workspace" {
  let request = workspace_request([
    (
      "morphir.toml", "[workspace]\nmembers=['one','two']\ndefault_member='one'\n[pipeline]\nbackend='scheme'\n",
    ),
    ("one/morphir.toml", "[project]\nname='One'\n"),
    ("one/src/main.scm", "42"),
    ("two/morphir.toml", "[project]\nname='Two'\n"),
    ("two/src/main.scm", "43"),
  ])
  let reply = @pipeline.execute(request)
  @expect.expect(reply)
  .at("projects")
  .get("count", value => {
    if value is Array(values) {
      values.length()
    } else {
      -1
    }
  })
  .to_equal(1)
  @expect.expect(reply).at("projects[0].path").to_equal("one")
  guard request is Object(fields) else { fail("request") }
  fields["projectPath"] = Json::string("two")
  let current = @pipeline.execute(Json::object(fields))
  @expect.expect(current).at("projects[0].path").to_equal("two")
  let empty = @pipeline.execute(
    workspace_request([("morphir.toml", "[workspace]\nmembers=[]\n")]),
  )
  @expect.expect(empty).at("success").to_equal(true)
  @expect.expect(empty).at("projects").to_equal(Json::array([]))
}

///|
test "workspace generation keeps shared settings and member overrides" {
  let reply = @pipeline.execute(
    workspace_request([
      (
        "morphir.toml", "[workspace]\nmembers=['one','two']\n[pipeline]\nbackend='scheme'\n",
      ),
      ("one/morphir.toml", "[project]\nname='One'\n"),
      ("one/src/main.scm", "42"),
      ("two/morphir.toml", "[project]\nname='Two'\n[pipeline]\nbackend='elm'\n"),
      ("two/src/main.scm", "43"),
    ]),
  )
  @expect.expect(reply).at("projects[0].target").to_equal("scheme")
  @expect.expect(reply).at("projects[1].target").to_equal("elm")
  @expect.expect(reply).at("success").to_equal(true)
}

///|
test "Compile and run uses the explicitly selected project" {
  let request = workspace_request([
    (
      "morphir.toml", "[workspace]\nmembers=['one','two']\n[pipeline]\nbackend='scheme'\n",
    ),
    ("one/morphir.toml", "[project]\nname='One'\n"),
    ("one/src/main.scm", "11"),
    ("two/morphir.toml", "[project]\nname='Two'\n"),
    ("two/src/main.scm", "22"),
  ])
  guard request is Object(fields) else { fail("request") }
  fields["operation"] = Json::string("run-project")
  fields["projectPath"] = Json::string("two")
  @expect.expect(@pipeline.execute(Json::object(fields)))
  .at("projects[0].result.value")
  .to_equal("22")
}
