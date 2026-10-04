///|
pub(all) struct Props {
  output : Json
  selected : String
  language : String
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
pub fn artifacts(output : Json) -> Array[Json] {
  match field(output, "artifacts") {
    Array(values) => values
    _ => []
  }
}

///|
pub fn selected(output : Json, path : String) -> Json {
  let files = artifacts(output)
  files
  .filter(file => text(file, "path") == path)
  .get(0)
  .unwrap_or(files.get(0).unwrap_or(Json::null()))
}

///|
fn language(path : String, fallback : String) -> String {
  if path.has_suffix(".elm") {
    "elm"
  } else if path.has_suffix(".json") {
    "json"
  } else {
    fallback
  }
}

///|
/// Generated source remains a set of files; the editor is a read-only projection.
pub fn view(
  props : Props,
  on_select : @cmd.Emit[String],
  on_download : @cmd.Emit[Bool],
) -> @html.Html {
  let files = artifacts(props.output)
  let file = selected(props.output, props.selected)
  let path = text(file, "path")
  let binary = field(file, "binary") == Json::boolean(true)
  let body : Array[@html.Html] = []
  if !files.is_empty() {
    body.push(
      @html.div(class="artifact-toolbar", [
        @html.label([
          @html.span(class="small muted", "File"),
          @html.select(
            attrs=@html.Attrs::build().aria_label("Generated file"),
            on_change=on_select,
            files.map(file => {
              @html.option(
                value=text(file, "path"),
                selected=text(file, "path") == path,
                text(file, "path"),
              )
            }),
          ),
        ]),
        @html.button(
          class="secondary",
          disabled=binary,
          on_click=on_download(false),
          "Download file",
        ),
        @html.button(
          class="secondary",
          disabled=files.any(f => field(f, "binary") == Json::boolean(true)),
          on_click=on_download(true),
          "Download project",
        ),
      ]),
    )
    if files.any(f => field(f, "binary") == Json::boolean(true)) {
      body.push(
        @html.p(
          class="small muted",
          "Binary files remain opaque; this host does not declare their download encoding.",
        ),
      )
    }
  }
  let message = text(props.output, "generationMessage")
  if message != "" {
    body.push(@html.p(class="generation-message", message))
  }
  match field(props.output, "generationWarnings") {
    Array(warnings) =>
      for warning in warnings {
        match warning {
          String(value) => body.push(@html.p(class="small muted", value))
          _ => ()
        }
      }
    _ => ()
  }
  body.push(
    @editor.view({
      id: "output",
      document_key: "generated|" + path,
      language: language(path, props.language),
      label: "Generated output",
      read_only: true,
      value: if binary {
        "Binary artifact: text preview unavailable"
      } else if file != Json::null() {
        text(file, "content")
      } else if text(props.output, "generated") != "" {
        text(props.output, "generated")
      } else if message != "" {
        "No files were generated. The compiled model remains available in Morphir IR."
      } else {
        "Select a generation target and recompile."
      },
    }),
  )
  @html.div(class="generated-output", body)
}
