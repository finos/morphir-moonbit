///|
fn refused(f : () -> @project.Project raise @project.ProjectError) -> Bool {
  try {
    ignore(f())
    false
  } catch {
    @project.ProjectError(_, _) => true
  }
}

///|
test "a project round-trips through the storage format" {
  let project = shop().add_file(elm_rules(), "src/Shop/Orders/Util.elm")
  @expect.expect_all(s => {
    s
    .expect(@project.Project::from_json(project.to_json()), label="round trip")
    .to_equal(project)
    s
    .expect(project.to_json(), label="shape")
    .to_contain_json({
      "version": 1,
      "name": "Shop.Orders",
      "languageId": "elm",
      "exposedModules": ["Api"],
      "active": "src/Shop/Orders/Util.elm",
    })
  })
}

///|
test "the worker request has the Plan B project shape" {
  @expect.expect(shop().to_request(), label="request").to_contain_json({
    "name": "Shop.Orders",
    "languageId": "elm",
    "exposedModules": ["Api"],
    "files": [
      {
        "path": "src/Shop/Orders/Api.elm",
        "content": "module Shop.Orders.Api exposing (..)\n",
      },
    ],
  })
}

///|
test "stored text that is not a valid project is refused" {
  let bad : Array[Json] = [
    {
      "version": 2,
      "name": "A",
      "languageId": "elm",
      "files": [],
      "active": "src/A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [],
      "active": "src/A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [{ "path": "../A.elm", "content": "" }],
      "active": "../A.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [{ "path": "src/A.elm", "content": "" }],
      "active": "src/B.elm",
    },
    {
      "version": 1,
      "name": "A",
      "languageId": "elm",
      "files": [
        { "path": "src/A.elm", "content": "" },
        { "path": "src/A.elm", "content": "" },
      ],
      "active": "src/A.elm",
    },
    Json::string("not an object"),
  ]
  @expect.expect_all(s => {
    for json in bad {
      s
      .expect(
        refused(() => @project.Project::from_json(json)),
        label=json.stringify(),
      )
      .to_be_true()
    }
  })
}

///|
test "a sample asset and its index parse" {
  let sample = @project.Sample::from_json({
    "version": 1,
    "id": "examples-tutorial",
    "title": "Rentals tutorial",
    "languageId": "elm",
    "notice": "From finos/morphir-examples, Apache-2.0.",
    "project": shop().to_json(),
  })
  @expect.expect_all(s => {
    s.expect(sample.id, label="id").to_equal("examples-tutorial")
    s.expect(sample.project, label="project").to_equal(shop())
    s
    .expect(
      @project.sample_index({
        "version": 1,
        "samples": [{ "id": "a", "title": "A" }],
      }),
      label="index",
    )
    .to_equal([("a", "A")])
  })
}

///|
test "problem counts come from frontendDiagnostics" {
  let counts = @project.problem_counts({
    "success": false,
    "frontendDiagnostics": [
      { "path": "src/A.elm", "problems": [{ "code": "x" }, { "code": "y" }] },
      { "path": "src/B.elm", "problems": [{ "code": "z" }] },
    ],
  })
  @expect.expect(counts, label="counts").to_equal({
    "src/A.elm": 2,
    "src/B.elm": 1,
  })
}

///|
/// Property: any project built from generated file names round-trips through storage and through the request
/// format (where the request keeps the files, the name and the exposed modules).
test "projects round-trip through storage and requests" {
  @expect.for_all(
    (names : Array[UInt32]) => {
      let mut project = shop()
      for n in names {
        project = project.add_file(
          elm_rules(),
          "src/Shop/Orders/M\{n % 50}.elm",
        ) catch {
          _ => project
        }
      }
      let back = @project.Project::from_request(project.to_request())
      @expect.expect_all(s => {
        s
        .expect(@project.Project::from_json(project.to_json()), label="storage")
        .to_equal(project)
        s.expect(back.files, label="request files").to_equal(project.files)
        s
        .expect(back.exposed, label="request exposed")
        .to_equal(project.exposed)
        s.expect(back.name, label="request name").to_equal(project.name)
      })
    },
    count=50,
  )
}

///|
/// Property: any JSON text either parses to a project or raises a ProjectError: a corrupt stored project never
/// crashes the page.
test "arbitrary JSON never aborts the loader" {
  @expect.for_all((chars : Array[Char]) => {
    let text = String::from_array(chars)
    match (@json.parse(text) catch { _ => Json::null() }) {
      json => {
        ignore(refused(() => @project.Project::from_json(json)))
        ignore(refused(() => @project.Project::from_request(json)))
        @expect.expect(
          @project.problem_counts(json).length() >= 0,
          label="counts",
        ).to_be_true()
      }
    }
  })
}
