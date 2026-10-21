///|
/// Compile the files the person edits. Only the browser's source-only validation policy is overlaid.
/// Projects execute independently so one failure cannot discard another project's results.
fn compile_workspace(engine : @engine.Engine, request : Json) -> Json raise {
  let files = @workspace_files.Files::from_json(
    @wire.field(request, "workspace"),
  )
  let tree = files.tree()
  let workspace = files.discover()
  let selector = optional_text(request, "projectPath").unwrap_or("")
  let projects = workspace.select(selector~)
  let host = @engine.Host::memory(tree.files)
  let overlay = @config.parse(
    "[pipeline]\nvalidation = 'source-only'\n",
    origin="Browser host",
  )
  let results : Array[Json] = []
  let artifacts : Array[Json] = []
  let mut successful = true
  for project in projects {
    let path = if project.root == workspace.root {
      "."
    } else if workspace.root == "" {
      project.root
    } else {
      project.root[workspace.root.length() + 1:].to_owned()
    }
    let language = project.document.text("frontend.language", "scheme")
    let target = project.document.text("pipeline.backend", "ir-json")
    let reply = try {
      if project.error is Some(message) {
        raise @config.Invalid(message)
      }
      let plan = engine.plan(host, workspace, {
        ..@engine.Request::new(),
        selector: path,
        overlay,
      })
      let units : Array[@data.IRUnit] = []
      let report = engine.execute_content(
        plan,
        fn(source, _) raise { @data.Text((host.read)(source)) },
        on_unit=compiled => units.push(compiled.unit),
      )
      let run : EngineRun = {
        unit: units.get(0),
        report,
        selection: plan.source_frontends().get(0),
      }
      let fields = compile_reply(
        run,
        @ids.LanguageId::parse(language),
        if target == "checkpoint" || target == "ir-json" {
          ""
        } else {
          target
        },
      )
      fields.push(("success", Json::boolean(report.successful())))
      fields.push(("artifacts", artifacts_json(report)))
      fields.push(
        (
          "units",
          Json::array(
            units.map(unit => {
              @wire.obj([
                ("ir", @codec.to_json(unit.distribution)),
                ("nodes", Json::array(describe(unit.distribution))),
              ])
            }),
          ),
        ),
      )
      @wire.obj(fields)
    } catch {
      CompileFailed(reply) => reply
      @config.Invalid(message) =>
        failure(message, "workbench.project_configuration", "compile")
      error =>
        failure(
          @scheme.error_message(error),
          "workbench.project_compile",
          "compile",
        )
    }
    if @wire.optional(reply, "success") != Some(Json::boolean(true)) {
      successful = false
    }
    let generated = match @wire.optional(reply, "artifacts") {
      Some(Array(items)) => items
      _ => []
    }
    for artifact in generated {
      guard artifact is Object(fields) else { continue }
      let fields = fields.copy()
      let file = @wire.string(@wire.field(artifact, "path"))
      fields["path"] = @wire.text(
        (if path == "." { "root" } else { "projects/" + path }) + "/" + file,
      )
      fields["projectPath"] = @wire.text(path)
      artifacts.push(Json::object(fields))
    }
    results.push(
      @wire.obj([
        ("path", @wire.text(path)),
        ("name", @wire.text(project.name)),
        ("languageId", @wire.text(language)),
        ("target", @wire.text(target)),
        ("result", reply),
      ]),
    )
  }
  @wire.obj([
    ("success", Json::boolean(successful)),
    ("projects", Json::array(results)),
    ("artifacts", Json::array(artifacts)),
    ("browserBuildPolicy", @wire.text("source-only")),
    ("discovery", workspace.to_json()),
  ])
}
