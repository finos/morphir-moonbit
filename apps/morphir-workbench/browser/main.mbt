///|
extern "js" fn host_request(request : String, receive : (String) -> Unit) =
  #| (request, receive) => globalThis.morphirWorkbench.request(JSON.parse(request), receive)

///|
extern "js" fn cancel_host() =
  #| () => globalThis.morphirWorkbench.cancel()

///|
extern "js" fn import_model(receive : (String) -> Unit) =
  #| (receive) => globalThis.morphirWorkbench.importModel(receive)

///|
extern "js" fn download_ir(text : String) =
  #| (text) => globalThis.morphirWorkbench.download(text)

///|
extern "js" fn download_generated(files : String, project : Bool) -> String =
  #| (files, project) => globalThis.morphirWorkbench.downloadArtifacts(JSON.parse(files), project)

///|
fn pretty(text : String) -> String {
  @json.parse(text).stringify(indent=2) catch {
    _ => text
  }
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
fn items(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
fn object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
let example : String =
  #|; A small, portable Morphir model
  #|(define (price quantity) (* quantity 12))
  #|(define (total quantity) (+ (price quantity) 5))
  #|(total 3)

///|
let moonbit_example : String =
  #|// One public function in the Boolean model profile
  #|pub fn eligible(active : Bool, vip : Bool) -> Bool {
  #|  active && !vip
  #|}

///|
let moonbit_library_example : String =
  #|fn gate(active : Bool) -> Bool { active }
  #|pub fn eligible(activeUser : Bool, vipMember : Bool) -> Bool {
  #|  let allowed = gate(activeUser)
  #|  allowed && !vipMember
  #|}
  #|pub fn welcome() -> Bool { eligible(true, false) }

///|
let worksheet_example : String =
  #|; Definitions live for this run
  #|(define (square x) (* x x))
  #|(square 7)
  #|(map square '(1 2 3 4))
  #|(+ 1/3 2/3)

///|
struct Location {
  explorer : Bool
  worksheet : Bool
  selected : String
  query : String
  explorer_raw : Bool
} derive(Eq)

///|
struct Model {
  history : Array[Location]
  explorer : Bool
  explorer_collapsed : Bool
  try_collapsed : Bool
  worksheet : Bool
  source : String
  worksheet_source : String
  drafts : Map[String, String]
  source_profile : String
  profile_choices : Map[String, String]
  explorer_raw : Bool
  collapsed_modules : Array[String]
  query : String
  selected : String
  evaluation_typed : Bool
  evaluation_mode : @evaluation.InputMode
  result_mode : @result.Mode
  evaluation_arguments : String
  evaluation_result : Json
  evaluation_revision : Int
  evaluation_result_revision : Int
  evaluation_entry : String
  model_revision : Int
  output : Json
  worksheet_output : Json
  model : Json
  generated : Bool
  generated_state : @generated.State
  status : String
  busy : Bool
  job : Int
  revision : Int
  worksheet_revision : Int
  output_revision : Int
  worksheet_output_revision : Int
  connected : Bool
  available : Bool
  catalog : Json
  language : String
  target : String
  projects : Array[Json]
} derive(Eq)

///|
enum Msg {
  Navigate(Bool)
  Back
  Collapse
  Layout(Bool)
  Source(String)
  EvaluationRuntime(Bool)
  EvaluationMode(@evaluation.InputMode)
  ResultMode(@result.Mode)
  EvaluationEdit(@arguments.Edit)
  EvaluationArguments(String)
  Evaluate
  ExplorerRaw(Bool)
  ToggleModule(String)
  Query(String)
  Select(String)
  OutputTab(Bool)
  Generated(@generated.Action)
  DownloadGenerated(Bool)
  Language(String)
  SourceProfile(String)
  Target(String)
  Example
  ElmExample
  MoonBitExample
  MoonBitLibraryExample
  DownloadSourceUnit
  Request(String)
  Receive(Int, Int, String, String)
  Cancel
  Import
  Imported(String)
  Export
  Project(String)
}

///|
extern "js" fn connected_mode() -> Bool = "() => globalThis.morphirWorkbench.connected"

///|
fn initial() -> Model {
  {
    history: [],
    explorer: false,
    explorer_collapsed: false,
    try_collapsed: false,
    worksheet: false,
    source: example,
    worksheet_source: worksheet_example,
    drafts: Map([]),
    source_profile: "",
    profile_choices: Map([]),
    explorer_raw: false,
    collapsed_modules: [],
    query: "",
    selected: "",
    evaluation_typed: false,
    evaluation_mode: @evaluation.Fields,
    result_mode: @result.Value,
    evaluation_arguments: "[]",
    evaluation_result: Json::null(),
    evaluation_revision: 0,
    evaluation_result_revision: -1,
    evaluation_entry: "",
    model_revision: 0,
    output: Json::null(),
    worksheet_output: Json::null(),
    model: Json::null(),
    generated: false,
    generated_state: @generated.State::new(),
    status: "Initializing…",
    busy: true,
    job: 0,
    revision: 0,
    worksheet_revision: 0,
    output_revision: -1,
    worksheet_output_revision: -1,
    connected: connected_mode(),
    available: false,
    catalog: Json::null(),
    language: "scheme",
    target: "",
    projects: [],
  }
}

///|
fn frontend(model : Model, language : String) -> Json {
  items(field(model.catalog, "frontends"))
  .filter(item => text(item, "languageId") == language)
  .get(0)
  .unwrap_or(Json::null())
}

///|
fn source_key(model : Model, language : String, profile : String) -> String {
  language + "|" + text(frontend(model, language), "providerId") + "|" + profile
}

///|
fn with_selection(model : Model, language : String, profile : String) -> Model {
  let drafts = model.drafts.copy()
  drafts[source_key(model, model.language, model.source_profile)] = model.source
  let profile_choices = model.profile_choices.copy()
  profile_choices[language] = profile
  let source = drafts
    .get(source_key(model, language, profile))
    .unwrap_or(
      if model.connected {
        ""
      } else if profile == "moonbit-model-bool-library-v1" {
        moonbit_library_example
      } else if language == "moonbit" {
        moonbit_example
      } else {
        example
      },
    )
  {
    ..model,
    language,
    source_profile: profile,
    source,
    drafts,
    profile_choices,
    revision: model.revision + 1,
  }
}

///|
fn with_language(model : Model, language : String) -> Model {
  let profile = if model.connected {
    ""
  } else {
    model.profile_choices
    .get(language)
    .unwrap_or(text(frontend(model, language), "defaultProfile"))
  }
  with_selection(model, language, profile)
}

///|
fn request_cmd(
  emit : @cmd.Emit[Msg],
  job : Int,
  revision : Int,
  request : Json,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    host_request(request.stringify(), reply => {
      scheduler.add(
        emit(Receive(job, revision, text(request, "operation"), reply)),
      )
    })
  })
}

///|
fn location(model : Model) -> Location {
  {
    explorer: model.explorer,
    worksheet: model.worksheet,
    selected: model.selected,
    query: model.query,
    explorer_raw: model.explorer_raw,
  }
}

///|
fn remember(model : Model, next : Model) -> Model {
  if location(model) == location(next) {
    return next
  }
  let history = model.history.copy()
  if history.length() == 100 {
    history.remove(0) |> ignore
  }
  history.push(location(model))
  { ..next, history, }
}

///|
fn select(model : Model, selected : String) -> Model {
  if selected == model.selected {
    return model
  }
  let profile = evaluation_profile(
    model.model,
    selected,
    model.evaluation_typed,
  )
  {
    ..model,
    selected,
    evaluation_arguments: default_arguments(
      profile,
      model.evaluation_mode,
      model.evaluation_typed,
    ),
    evaluation_result: Json::null(),
    evaluation_revision: model.evaluation_revision + 1,
  }
}

// A replacement IR invalidates declaration destinations, but experience history
// still lets the user return to the editor. Coalesce destinations after resetting.

///|
fn replacement_history(model : Model) -> Array[Location] {
  let history : Array[Location] = []
  for entry in model.history {
    let entry = { ..entry, selected: "", query: "", }
    if history.last() != Some(entry) {
      history.push(entry)
    }
  }
  let current = { ..location(model), selected: "", query: "", }
  if history.last() == Some(current) {
    history.pop() |> ignore
  }
  history
}

///|
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    Navigate(explorer) => (remember(model, { ..model, explorer, }), @cmd.none)
    Back => {
      let history = model.history.copy()
      match history.pop() {
        None => (model, @cmd.none)
        Some(previous) => {
          let restored = select(model, previous.selected)
          (
            {
              ..restored,
              history,
              explorer: previous.explorer,
              worksheet: previous.worksheet,
              query: previous.query,
              explorer_raw: previous.explorer_raw,
            },
            @cmd.none,
          )
        }
      }
    }
    Collapse =>
      (
        if model.explorer {
          { ..model, explorer_collapsed: !model.explorer_collapsed, }
        } else {
          { ..model, try_collapsed: !model.try_collapsed, }
        },
        @cmd.none,
      )
    Layout(worksheet) => (remember(model, { ..model, worksheet, }), @cmd.none)
    Source(source) =>
      (
        if model.worksheet {
          {
            ..model,
            worksheet_source: source,
            worksheet_revision: model.worksheet_revision + 1,
          }
        } else {
          { ..model, source, revision: model.revision + 1, }
        },
        @cmd.none,
      )
    ExplorerRaw(raw) => ({ ..model, explorer_raw: raw, }, @cmd.none)
    ToggleModule(id) => {
      let collapsed_modules = if model.collapsed_modules.contains(id) {
        model.collapsed_modules.filter(module_id => module_id != id)
      } else {
        let modules = model.collapsed_modules.copy()
        modules.push(id)
        modules
      }
      ({ ..model, collapsed_modules, }, @cmd.none)
    }
    Query(query) => ({ ..model, query, }, @cmd.none)
    Select(selected) => (remember(model, select(model, selected)), @cmd.none)
    EvaluationRuntime(evaluation_typed) => {
      if evaluation_typed == model.evaluation_typed {
        return (model, @cmd.none)
      }
      let profile = evaluation_profile(
        model.model,
        model.selected,
        evaluation_typed,
      )
      // Invalidate the request ID as well as resetting the argument document.
      // A held reply from the previous runtime must not replace this result.
      (
        {
          ..model,
          evaluation_typed,
          evaluation_arguments: default_arguments(
            profile,
            model.evaluation_mode,
            evaluation_typed,
          ),
          evaluation_result: Json::null(),
          evaluation_revision: model.evaluation_revision + 1,
          job: model.job + 1,
          busy: false,
          status: "Evaluation mode changed",
        },
        @cmd.custom_cmd(_ => cancel_host()),
      )
    }
    EvaluationMode(evaluation_mode) => {
      let profile = evaluation_profile(
        model.model,
        model.selected,
        model.evaluation_typed,
      )
      let evaluation_arguments = @arguments.convert_inputs(
        profile,
        model.evaluation_arguments,
        model.evaluation_mode == @evaluation.Ion,
        evaluation_mode == @evaluation.Ion,
        model.evaluation_typed,
      ) catch {
        error =>
          return (
            {
              ..model,
              status: "Cannot switch inputs: " + @arguments.input_error(error),
            },
            @cmd.none,
          )
      }
      ({ ..model, evaluation_mode, evaluation_arguments, }, @cmd.none)
    }
    ResultMode(result_mode) => ({ ..model, result_mode, }, @cmd.none)
    EvaluationEdit(edit) => {
      let evaluation_arguments = @arguments.edit(
        model.evaluation_arguments,
        edit,
      ) catch {
        _ =>
          return (
            {
              ..model,
              status: "Input fields could not apply this edit. Check JSON inputs.",
            },
            @cmd.none,
          )
      }
      (
        {
          ..model,
          evaluation_arguments,
          evaluation_revision: model.evaluation_revision + 1,
        },
        @cmd.none,
      )
    }
    EvaluationArguments(evaluation_arguments) =>
      (
        {
          ..model,
          evaluation_arguments,
          evaluation_revision: model.evaluation_revision + 1,
        },
        @cmd.none,
      )
    Evaluate => {
      let profile = evaluation_profile(
        model.model,
        model.selected,
        model.evaluation_typed,
      )
      if model.busy ||
        model.connected ||
        field(profile, "supported") != Json::boolean(true) {
        return (model, @cmd.none)
      }
      if model.evaluation_arguments.length() > 16 * 1024 * 1024 {
        return (
          { ..model, status: "Function arguments exceed the 16-MiB limit", },
          @cmd.none,
        )
      }
      let arguments = try {
        if model.evaluation_mode == @evaluation.Ion {
          Json::null()
        } else {
          @json.parse(model.evaluation_arguments)
        }
      } catch {
        _ =>
          return (
            {
              ..model,
              evaluation_result: object([
                ("success", Json::boolean(false)),
                (
                  "message",
                  Json::string("Arguments must be a valid JSON array"),
                ),
              ]),
              status: "Invalid evaluation inputs",
              evaluation_result_revision: model.evaluation_revision,
            },
            @cmd.none,
          )
      }
      let job = model.job + 1
      (
        {
          ..model,
          job,
          busy: true,
          evaluation_entry: model.selected,
          status: "Evaluating function…",
        },
        request_cmd(
          emit,
          job,
          model.evaluation_revision,
          object([
            ("operation", Json::string("evaluate")),
            ("source", Json::string(model_source(model.model))),
            (
              "entry",
              Json::string(
                model.selected
                .strip_prefix("value|")
                .unwrap_or(model.selected[:])
                .to_owned(),
              ),
            ),
            ("arguments", arguments),
            (
              "argumentsIon",
              if model.evaluation_mode == @evaluation.Ion {
                Json::string(model.evaluation_arguments)
              } else {
                Json::null()
              },
            ),
            (
              "executionMode",
              Json::string(
                if model.evaluation_typed {
                  "typed"
                } else {
                  "local"
                },
              ),
            ),
          ]),
        ),
      )
    }
    OutputTab(generated) => ({ ..model, generated, }, @cmd.none)
    Generated(action) =>
      (
        { ..model, generated_state: model.generated_state.update(action), },
        @cmd.none,
      )
    DownloadGenerated(project) => {
      let files = if project {
        @generated.artifacts(model.output)
      } else {
        [@generated.selected(model.output, model.generated_state.selected)]
      }
      let message = download_generated(Json::array(files).stringify(), project)
      (
        {
          ..model,
          status: if message == "" {
            "Generated files downloaded"
          } else {
            message
          },
        },
        @cmd.none,
      )
    }
    Language(language) => (with_language(model, language), @cmd.none)
    SourceProfile(profile) =>
      (with_selection(model, model.language, profile), @cmd.none)
    Target(target) =>
      ({ ..model, target, revision: model.revision + 1, }, @cmd.none)
    Example =>
      (
        {
          ..with_language(model, "scheme"),
          source: example,
          worksheet_source: worksheet_example,
          revision: model.revision + 1,
          worksheet_revision: model.worksheet_revision + 1,
        },
        @cmd.none,
      )
    ElmExample =>
      (
        {
          ..with_language(model, "scheme"),
          source: "; Generate an Elm library with Compile\n(define answer 42)",
          target: "elm",
          revision: model.revision + 1,
        },
        @cmd.none,
      )
    MoonBitExample =>
      (
        {
          ..with_selection(model, "moonbit", "moonbit-model-bool-v1"),
          source: moonbit_example,
          target: "moonbit",
        },
        @cmd.none,
      )
    MoonBitLibraryExample =>
      (
        {
          ..with_selection(model, "moonbit", "moonbit-model-bool-library-v1"),
          source: moonbit_library_example,
          target: "moonbit",
        },
        @cmd.none,
      )
    DownloadSourceUnit => {
      let source = text(model.output, "sourceUnitIon")
      if source == "" {
        return (model, @cmd.none)
      }
      let message = download_generated(
        Json::array([
          object([
            ("path", Json::string("main.ion")),
            ("content", Json::string(source)),
            ("binary", Json::boolean(false)),
          ]),
        ]).stringify(),
        false,
      )
      (
        {
          ..model,
          status: if message == "" {
            "Source unit downloaded"
          } else {
            message
          },
        },
        @cmd.none,
      )
    }
    Request(operation) => {
      let job = model.job + 1
      let fields : Array[(String, Json)] = [
        ("operation", Json::string(operation)),
        (
          "source",
          Json::string(
            if model.worksheet {
              model.worksheet_source
            } else {
              model.source
            },
          ),
        ),
        (
          "languageId",
          Json::string(if model.worksheet { "scheme" } else { model.language }),
        ),
        ("target", Json::string(model.target)),
      ]
      if !model.connected && !model.worksheet && model.language == "moonbit" {
        fields.push(
          (
            "frontendProvider",
            Json::string(text(frontend(model, model.language), "providerId")),
          ),
        )
        fields.push(("frontendProfile", Json::string(model.source_profile)))
      }
      let request = object(fields)
      (
        { ..model, job, busy: true, status: "Working…", },
        request_cmd(
          emit,
          job,
          if operation == "worksheet" {
            model.worksheet_revision
          } else {
            model.revision
          },
          request,
        ),
      )
    }
    Receive(job, revision, operation, reply) => {
      if job != model.job {
        return (model, @cmd.none)
      }
      let result = @json.parse(reply) catch {
        _ =>
          object([
            ("success", Json::boolean(false)),
            ("message", Json::string("Invalid host response")),
          ])
      }
      if operation == "evaluate" {
        if model.evaluation_entry != model.selected {
          return (
            { ..model, busy: false, status: "Finished for another function", },
            @cmd.none,
          )
        }
        return (
          {
            ..model,
            busy: false,
            evaluation_result: result,
            evaluation_result_revision: revision,
            status: if revision != model.evaluation_revision {
              "Finished for earlier inputs"
            } else if field(result, "success") == Json::boolean(true) {
              "Function evaluated"
            } else {
              "Evaluation failed"
            },
          },
          @cmd.none,
        )
      }
      if field(result, "success") != Json::boolean(true) {
        return (
          { ..model, busy: false, status: text(result, "message"), },
          @cmd.none,
        )
      }
      if text(result, "operation") == "initialize" {
        let catalog = field(result, "catalog")
        let frontends = items(field(catalog, "frontends"))
        let language = if frontends.length() > 0 {
          text(frontends[0], "languageId")
        } else {
          ""
        }
        return (
          {
            ..model,
            busy: false,
            connected: field(result, "connected") == Json::boolean(true),
            available: !frontends.is_empty(),
            catalog,
            language,
            target: if model.connected {
              ""
            } else {
              "scheme"
            },
            source: if model.connected {
              ""
            } else {
              model.source
            },
            projects: items(field(result, "projects")),
            status: text(result, "message"),
          },
          @cmd.none,
        )
      }
      let compiled = field(result, "ir") != Json::null()
      let worksheet_result = field(result, "results") != Json::null()
      if worksheet_result {
        return (
          {
            ..model,
            busy: false,
            worksheet_output: result,
            worksheet_output_revision: revision,
            status: if revision == model.worksheet_revision {
              "Worksheet finished"
            } else {
              "Finished for an earlier worksheet revision"
            },
          },
          @cmd.none,
        )
      }
      (
        {
          ..model,
          busy: false,
          output: if operation == "inspect" || operation == "project" {
            model.output
          } else {
            result
          },
          history: if compiled {
            replacement_history(model)
          } else {
            model.history
          },
          model_revision: if compiled {
            model.model_revision + 1
          } else {
            model.model_revision
          },
          evaluation_result: if compiled {
            Json::null()
          } else {
            model.evaluation_result
          },
          evaluation_arguments: if compiled {
            "[]"
          } else {
            model.evaluation_arguments
          },
          evaluation_typed: if compiled {
            text(result, "sourceProfile") == "moonbit-model-bool-v1" ||
            text(result, "sourceProfile") == "moonbit-model-bool-library-v1"
          } else {
            model.evaluation_typed
          },
          model: if compiled {
            result
          } else {
            model.model
          },
          query: if compiled {
            ""
          } else {
            model.query
          },
          collapsed_modules: if compiled {
            []
          } else {
            model.collapsed_modules
          },
          selected: if compiled {
            ""
          } else {
            model.selected
          },
          output_revision: if operation == "inspect" || operation == "project" {
            model.output_revision
          } else {
            revision
          },
          generated_state: if operation == "compile" || operation == "run" {
            model.generated_state.reset()
          } else {
            model.generated_state
          },
          status: if revision == model.revision {
            if text(result, "generationMessage") != "" {
              text(result, "generationMessage")
            } else if text(result, "inspectionMessage") != "" {
              text(result, "inspectionMessage")
            } else {
              "Model ready"
            }
          } else {
            "Finished for an earlier source revision"
          },
        },
        @cmd.none,
      )
    }
    Cancel =>
      (
        {
          ..model,
          busy: false,
          job: model.job + 1,
          status: if model.connected {
            "Discarded. The host may still be working."
          } else {
            "Cancelled"
          },
        },
        @cmd.custom_cmd(_ => cancel_host()),
      )
    Import =>
      (
        model,
        @cmd.custom_cmd(scheduler => {
          import_model(reply => scheduler.add(emit(Imported(reply))))
        }),
      )
    Imported(source) => {
      if source == "{\"oversizedImport\":true}" {
        return (
          { ..model, status: "Model import exceeds the 16-MiB limit", },
          @cmd.none,
        )
      }
      if source == "{\"unreadableImport\":true}" {
        return (
          { ..model, status: "Could not read the selected model file", },
          @cmd.none,
        )
      }
      let job = model.job + 1
      (
        remember(model, {
          ..model,
          explorer: true,
          job,
          busy: true,
          status: "Reading model…",
        }),
        request_cmd(
          emit,
          job,
          model.revision,
          object([
            ("operation", Json::string("inspect")),
            ("source", Json::string(source)),
          ]),
        ),
      )
    }
    Export =>
      (model, @cmd.custom_cmd(_ => download_ir(model_source(model.model))))
    Project(project) => {
      let job = model.job + 1
      (
        { ..model, job, busy: true, status: "Opening project model…", },
        request_cmd(
          emit,
          job,
          model.revision,
          object([
            ("operation", Json::string("project")),
            ("project", Json::string(project)),
          ]),
        ),
      )
    }
  }
}

///|
fn nav_button(
  emit : @cmd.Emit[Msg],
  active : Bool,
  icon : String,
  label : String,
  msg : Msg,
) -> @html.Html {
  @html.button(
    class=if active { "nav-item active" } else { "nav-item" },
    title=label,
    attrs=@html.Attrs::build()
      .aria_label(label)
      .aria_pressed(active.to_string()),
    on_click=emit(msg),
    [
      @html.span(
        class="nav-icon " + icon,
        attrs=@html.Attrs::build().aria_hidden("true"),
        "",
      ),
      @html.span(class="nav-label", label),
    ],
  )
}

///|
fn sidebar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let context : Array[@html.Html] = []
  if model.explorer {
    context.push(@html.p(class="eyebrow", "MODEL EXPLORER"))
    context.push(
      @html.input(
        placeholder="Find a declaration…",
        value=model.query,
        attrs=@html.Attrs::build().aria_label("Find a declaration"),
        on_input=emit.map(value => Query(value)),
      ),
    )
    context.push(
      @explorer.navigation(
        explorer_props(model),
        emit.map(id => Select(id)),
        emit.map(id => ToggleModule(id)),
      ),
    )
    context.push(
      @html.button(
        class="secondary full",
        disabled=model.busy,
        on_click=emit(Import),
        "Import model",
      ),
    )
    for project in model.projects {
      context.push(
        @html.button(
          class="tree-item",
          on_click=emit(Project(text(project, "id"))),
          text(project, "name"),
        ),
      )
    }
  } else {
    context.push(@html.p(class="eyebrow", "TRY MORPHIR"))
    context.push(
      @html.p(
        class="context-title",
        if model.worksheet {
          "Worksheet"
        } else {
          "Compile & inspect"
        },
      ),
    )
    context.push(
      @html.p(
        class="muted",
        if model.worksheet {
          "Each expression gets a result. Definitions are shared within one run."
        } else {
          "Turn source into a portable model. Inspect the IR and generated output."
        },
      ),
    )
    context.push(@html.p(class="eyebrow", "EXAMPLES"))
    context.push(
      @html.button(
        class="tree-item",
        disabled=model.connected || model.busy,
        on_click=emit(Example),
        "Pricing & arithmetic",
      ),
    )
    context.push(
      @html.button(
        class="tree-item",
        disabled=model.connected || model.busy,
        hidden=model.worksheet,
        on_click=emit(ElmExample),
        "Elm constant",
      ),
    )
    context.push(
      @html.button(
        class="tree-item",
        disabled=model.connected || model.busy,
        hidden=model.worksheet,
        on_click=emit(MoonBitExample),
        "MoonBit Boolean",
      ),
    )
    context.push(
      @html.button(
        class="tree-item",
        disabled=model.connected || model.busy,
        hidden=model.worksheet,
        on_click=emit(MoonBitLibraryExample),
        "MoonBit library",
      ),
    )
    context.push(
      @html.p(
        class="muted small",
        if model.connected {
          "Languages and targets come from your connected host."
        } else {
          "Scheme and MoonBit Boolean profiles compile locally. Your source stays in this browser."
        },
      ),
    )
  }
  @html.aside(id="sidebar", [
    @html.div(class="brand", [
      @html.img(class="brand-mark", src="./morphir-mark.svg", alt="Morphir"),
      @html.img(
        class="brand-logo nav-label",
        src="./morphir-logo.svg",
        alt="Morphir",
      ),
    ]),
    @html.nav(attrs=@html.Attrs::build().aria_label("Experiences"), [
      nav_button(
        emit,
        model.explorer,
        "icon-model",
        "Model Explorer",
        Navigate(true),
      ),
      nav_button(
        emit,
        !model.explorer,
        "icon-code",
        "Try Morphir",
        Navigate(false),
      ),
    ]),
    @html.div(id="context-navigation", class="context", context),
    @html.div(class="sidebar-bottom", [
      @html.span(class="nav-label muted small", "Shared workbench"),
      @html.button(
        class="collapse",
        title="Toggle sidebar",
        attrs=@html.Attrs::build()
          .aria_label("Toggle sidebar")
          .aria_controls("context-navigation")
          .aria_expanded(
            (!(if model.explorer {
              model.explorer_collapsed
            } else {
              model.try_collapsed
            })).to_string(),
          ),
        on_click=emit(Collapse),
        @html.span(
          class="nav-icon icon-sidebar",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
      ),
    ]),
  ])
}

///|
fn output_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let output = if model.worksheet {
    model.worksheet_output
  } else {
    model.output
  }
  let revision = if model.worksheet {
    model.worksheet_revision
  } else {
    model.revision
  }
  let output_revision = if model.worksheet {
    model.worksheet_output_revision
  } else {
    model.output_revision
  }
  let results = items(field(output, "results"))
  let body : Array[@html.Html] = []
  if text(output, "value") != "" {
    body.push(
      @html.div(class="run-value", [
        @html.span(class="muted", "Result"),
        @html.strong(text(output, "value")),
      ]),
    )
  }
  if model.worksheet && field(output, "results") != Json::null() {
    if results.is_empty() {
      body.push(@html.p(class="muted", "No expressions to run."))
    }
    for result in results {
      body.push(
        @html.div(class="worksheet-result", [
          @html.pre(class="expression", text(result, "expression")),
          @html.pre(class="value", text(result, "value")),
        ]),
      )
    }
  } else if model.generated {
    body.push(
      @generated.view(
        { output, state: model.generated_state, language: model.target, },
        emit.map(action => Generated(action)),
        emit.map(project => DownloadGenerated(project)),
      ),
    )
  } else {
    body.push(
      @editor.view({
        id: "output",
        document_key: "output",
        language: "json",
        label: "Morphir IR",
        read_only: true,
        value: if field(output, "ir") == Json::null() {
          "Your compiled model will appear here."
        } else {
          pretty(model_source(output))
        },
      }),
    )
  }
  @html.section(class="panel output-panel", [
    @html.div(class="panel-heading", [
      @html.div(class="tabs", [
        @html.button(
          class=if !model.generated { "tab selected" } else { "tab" },
          on_click=emit(OutputTab(false)),
          if model.worksheet {
            "Results"
          } else {
            "Morphir IR"
          },
        ),
        @html.button(
          class=if model.generated { "tab selected" } else { "tab" },
          hidden=model.worksheet,
          on_click=emit(OutputTab(true)),
          "Generated",
        ),
      ]),
      @html.button(
        class="secondary",
        hidden=model.worksheet || text(output, "sourceUnitIon") == "",
        title="Download the rich Ion source unit, including metadata and provenance",
        on_click=emit(DownloadSourceUnit),
        "Download source unit",
      ),
      @html.span(
        class="muted small",
        if output_revision >= 0 && output_revision != revision {
          "Source changed · rerun"
        } else {
          ""
        },
      ),
    ]),
    @html.div(class="output-body", body),
  ])
}

///|
fn source_name(model : Model) -> String {
  for frontend in items(field(model.catalog, "frontends")) {
    if text(frontend, "languageId") == model.language {
      let extensions = items(field(frontend, "fileExtensions"))
      if extensions.length() > 0 && extensions[0] is String(extension) {
        return "main" + extension
      }
    }
  }
  "main.scm"
}

///|
fn playground(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let languages = items(field(model.catalog, "frontends")).map(frontend => {
    @html.option(
      value=text(frontend, "languageId"),
      selected=text(frontend, "languageId") ==
        (if model.worksheet { "scheme" } else { model.language }),
      text(frontend, "displayName"),
    )
  })
  let targets = [
    @html.option(value="", selected=model.target == "", "No generation"),
  ]
  for target in items(field(model.catalog, "targets")) {
    targets.push(
      @html.option(
        value=text(target, "target"),
        selected=text(target, "target") == model.target,
        text(target, "displayName"),
      ),
    )
  }
  @html.div(class="experience", [
    @html.div(class="experience-heading", [
      @html.div([
        @html.p(class="eyebrow", "A PLACE TO EXPERIMENT"),
        @html.h1("Try Morphir"),
        @html.p(class="muted", "Write a little. See the model. Run it."),
      ]),
      @html.div(class="mode-switch", [
        @html.button(
          class=if !model.worksheet { "selected" } else { "" },
          attrs=@html.Attrs::build().aria_pressed(
            (!model.worksheet).to_string(),
          ),
          on_click=emit(Layout(false)),
          "Compile & inspect",
        ),
        @html.button(
          class=if model.worksheet { "selected" } else { "" },
          disabled=model.connected,
          title=if model.connected {
            "The connected v1 protocol does not offer evaluation"
          } else {
            ""
          },
          attrs=@html.Attrs::build().aria_pressed(model.worksheet.to_string()),
          on_click=emit(Layout(true)),
          "Worksheet",
        ),
      ]),
    ]),
    @html.div(class="toolbar", [
      @html.label([
        @html.span(class="small muted", "Language"),
        @html.select(
          disabled=model.busy || model.worksheet,
          on_change=emit.map(value => Language(value)),
          attrs=@html.Attrs::build()
            .aria_label("Language")
            .value_prop(if model.worksheet { "scheme" } else { model.language }),
          languages,
        ),
      ]),
      @html.div(hidden=model.connected || model.worksheet, [
        @source_selection.view(
          {
            frontend: frontend(model, model.language),
            profile: model.source_profile,
            busy: model.busy,
          },
          on_change=emit.map(value => SourceProfile(value)),
        ),
      ]),
      @html.label(hidden=model.worksheet, [
        @html.span(class="small muted", "Target"),
        @html.select(
          disabled=model.busy,
          on_change=emit.map(value => Target(value)),
          attrs=@html.Attrs::build()
            .aria_label("Target")
            .value_prop(model.target),
          targets,
        ),
      ]),
      @html.div(class="toolbar-actions", [
        @html.button(
          class="secondary",
          disabled=model.busy || model.worksheet || !model.available,
          on_click=emit(Request("compile")),
          "Compile",
        ),
        @html.button(
          class="primary",
          disabled=model.busy ||
            model.connected ||
            !model.available ||
            (!model.worksheet && model.language != "scheme"),
          title=if model.connected {
            "This host does not advertise an evaluation method"
          } else if !model.worksheet && model.language != "scheme" {
            "Compile, then select a public function in Model Explorer to enter inputs and evaluate"
          } else if model.target != "scheme" {
            "Generate source and evaluate the model with the local Scheme runtime"
          } else {
            ""
          },
          on_click=emit(
            Request(if model.worksheet { "worksheet" } else { "run" }),
          ),
          if model.worksheet {
            "Run worksheet"
          } else if !model.connected && model.language == "moonbit" {
            "Evaluate in Explorer"
          } else if !model.connected && model.target != "scheme" {
            "Compile & run (Scheme)"
          } else {
            "Compile & run"
          },
        ),
        @html.button(
          class="secondary",
          hidden=!model.busy || model.job == 0,
          on_click=emit(Cancel),
          if model.connected {
            "Discard"
          } else {
            "Cancel"
          },
        ),
      ]),
    ]),
    @html.div(hidden=model.connected || model.worksheet, [
      @source_selection.capabilities({
        frontend: frontend(model, model.language),
        profile: model.source_profile,
        busy: model.busy,
      }),
    ]),
    @html.div(
      class=if model.generated &&
        !model.worksheet &&
        model.generated_state.expanded {
        "editor-grid output-expanded"
      } else {
        "editor-grid"
      },
      [
        @html.section(class="panel source-panel", [
          @html.div(class="panel-heading", [
            @html.span(
              if model.worksheet {
                "worksheet.scm"
              } else {
                source_name(model)
              },
            ),
            @html.span(class="muted small", "Editable source"),
          ]),
          @editor.view(
            {
              id: "source",
              document_key: if model.worksheet {
                "worksheet-source"
              } else {
                "compile-source|" +
                source_key(model, model.language, model.source_profile)
              },
              value: if model.worksheet {
                model.worksheet_source
              } else {
                model.source
              },
              language: if model.worksheet {
                "scheme"
              } else {
                model.language
              },
              label: "Source editor",
              read_only: false,
            },
            on_change=emit.map(value => Source(value)),
          ),
        ]),
        output_panel(model, emit),
      ],
    ),
    @html.p(
      class="muted small footnote",
      if model.connected {
        "Compile and generate use the connected Morphir v1 protocol."
      } else if model.worksheet {
        "Scheme worksheet results are dynamic values; this runtime does not infer Scala-style types."
      } else if model.language == "moonbit" {
        "Compile the selected MoonBit profile, then select a public function in Model Explorer to enter inputs and evaluate."
      } else if model.target == "elm" {
        "For an Elm library, use named definitions. Scheme does not infer types."
      } else {
        "The Scheme frontend lowers a functional subset to IR. It does not perform type inference."
      },
    ),
  ])
}

///|
fn explorer(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="experience", [
    @html.div(class="experience-heading", [
      @html.div([
        @html.p(class="eyebrow", "UNDERSTAND YOUR MODEL"),
        @html.h1("Model Explorer"),
        @html.p(
          class="muted",
          "Packages, modules, types and values — in one place.",
        ),
      ]),
      @html.div(class="toolbar-actions", [
        @html.button(
          class="secondary",
          disabled=!model.busy,
          on_click=emit(Cancel),
          if model.connected {
            "Discard"
          } else {
            "Cancel"
          },
        ),
        @html.button(
          class="secondary",
          disabled=model.busy,
          on_click=emit(Import),
          "Import model",
        ),
        @html.button(
          class="secondary",
          disabled=field(model.model, "ir") == Json::null(),
          on_click=emit(Export),
          "Export IR",
        ),
      ]),
    ]),
    @explorer.details(
      explorer_props(model),
      emit.map(id => Select(id)),
      emit.map(raw => ExplorerRaw(raw)),
      @evaluation.view(
        {
          typed: model.evaluation_typed,
          input_mode: model.evaluation_mode,
          result_mode: model.result_mode,
          profile: evaluation_profile(
            model.model,
            model.selected,
            model.evaluation_typed,
          ),
          document_key: "evaluation-" +
          model.model_revision.to_string() +
          "-" +
          model.selected +
          "-" +
          model.evaluation_typed.to_string(),
          arguments: model.evaluation_arguments,
          result: model.evaluation_result,
          stale: model.evaluation_result_revision != model.evaluation_revision,
          busy: model.busy,
          connected: model.connected,
        },
        emit.map(value => EvaluationArguments(value)),
        emit(Evaluate),
        emit.map(value => EvaluationMode(value)),
        emit.map(edit => EvaluationEdit(edit)),
        emit.map(mode => ResultMode(mode)),
        emit.map(mode => EvaluationRuntime(mode)),
      ),
    ),
  ])
}

///|
fn view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let collapsed = if model.explorer {
    model.explorer_collapsed
  } else {
    model.try_collapsed
  }
  @html.div(class=if collapsed { "workbench collapsed" } else { "workbench" }, [
    sidebar(model, emit),
    @html.main_([
      @html.header(class="topbar", [
        @html.div(class="navigation-history", [
          @html.button(
            class="back-button",
            title="Back",
            attrs=@html.Attrs::build().aria_label("Back"),
            disabled=model.history.is_empty(),
            on_click=emit(Back),
            @html.span(
              class="nav-icon icon-back",
              attrs=@html.Attrs::build().aria_hidden("true"),
              "",
            ),
          ),
          @html.span(
            class="breadcrumb",
            if model.explorer {
              "Workbench / Model Explorer"
            } else {
              "Workbench / Try Morphir"
            },
          ),
        ]),
        @html.div(class="connection", [
          @html.span(class="connection-dot", "●"),
          @html.span(
            if model.connected {
              "Connected host"
            } else {
              "Browser local"
            },
          ),
          @html.a(
            href=if model.connected { "?mode=local" } else { "?mode=connected" },
            class="small",
            if model.connected {
              "Use local"
            } else {
              "Connect"
            },
          ),
        ]),
      ]),
      if model.explorer {
        explorer(model, emit)
      } else {
        playground(model, emit)
      },
      @html.footer(
        class="statusbar",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        [
          @html.span(
            if model.busy {
              "◌ " + model.status
            } else {
              model.status
            },
          ),
          @html.span(class="muted small", "Morphir · MoonBit / Rabbita"),
        ],
      ),
    ]),
  ])
}

///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        (
          initial(),
          request_cmd(
            emit,
            0,
            0,
            object([("operation", Json::string("initialize"))]),
          ),
        )
      },
      update~,
    )
    model.view(model => view(model, emit))
  }).mount("app")
}

///|
fn explorer_props(model : Model) -> @explorer.Props {
  {
    data: model.model,
    selected: model.selected,
    query: model.query,
    collapsed_modules: model.collapsed_modules,
    raw: model.explorer_raw,
  }
}

///|
fn evaluation_profile(data : Json, selected : String, typed : Bool) -> Json {
  let profiles = if typed {
    let manifest = field(data, "typedEvaluations")
    let entry = field(
      field(manifest, "entries"),
      selected.strip_prefix("value|").unwrap_or(selected[:]).to_owned(),
    )
    if entry == Json::null() {
      return object([
        ("supported", Json::boolean(false)),
        (
          "reason",
          Json::string(
            if text(manifest, "reason") != "" {
              text(manifest, "reason")
            } else {
              "Typed evaluation requires a public entry with supported input and output types."
            },
          ),
        ),
      ])
    }
    field(manifest, "entries")
  } else {
    field(data, "evaluations")
  }
  let profile = field(
    profiles,
    selected.strip_prefix("value|").unwrap_or(selected[:]).to_owned(),
  )
  if profile == Json::null() {
    object([
      ("supported", Json::boolean(false)),
      ("reason", Json::string("Only public functions can be evaluated.")),
    ])
  } else {
    profile
  }
}

///|
/// Keep exact JSON number lexemes out of the JavaScript object transport.
fn model_source(data : Json) -> String {
  if text(data, "irSource") != "" {
    text(data, "irSource")
  } else {
    field(data, "ir").stringify()
  }
}

///|
fn default_arguments(
  profile : Json,
  mode : @evaluation.InputMode,
  typed : Bool,
) -> String {
  let json = pretty(field(profile, "default").stringify())
  if mode == @evaluation.Ion {
    @arguments.convert_inputs(profile, json, false, true, typed) catch {
      _ => "[]"
    }
  } else {
    json
  }
}
