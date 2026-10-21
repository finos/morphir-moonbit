///|
/// Persistent workspace files. Project identity and effective settings are rediscovered from these files.
/// `open_file` is workspace-relative; the innermost project owning it is current.
pub struct Files {
  priv contents : Map[String, String]
  priv open_file : String?
  priv selected_project : @discovery.ProjectPath?
} derive(Eq, Debug)

///|
pub extend Files with Eq::{equal, not_equal}

///|
pub extend Files with @debug.Debug::{to_repr}

///|
pub fn Files::new(
  contents : Map[String, String],
  open_file~ : String? = None,
  current_project~ : @discovery.ProjectPath? = None,
) -> Files raise {
  if contents.length() > 2000 ||
    contents
    .iter()
    .fold(init=0, fn(n, entry) {
      n + @utf8.encode(entry.0).length() + @utf8.encode(entry.1).length()
    }) >
    16 * 1024 * 1024 {
    raise @config.Invalid(
      "A workspace can hold at most 2000 files and 16 MiB of text",
    )
  }
  ignore(@discovery.Tree::from_files(contents))
  for path, _ in contents {
    ignore(@ids.SourcePath::parse(path))
  }
  if open_file is Some(path) && !contents.contains(path) {
    raise @config.Invalid("Open file is not in the workspace: " + path)
  }
  let files = {
    contents: contents.copy(),
    open_file,
    selected_project: current_project,
  }
  { ..files, selected_project: files.current() catch { _ => current_project }, }
}

///|
pub fn Files::tree(self : Files) -> @discovery.Tree raise {
  @discovery.Tree::from_files(self.contents)
}

///|
pub fn Files::paths(self : Files) -> Array[String] {
  let paths = self.contents.keys().collect()
  paths.sort()
  paths
}

///|
pub fn Files::read(self : Files, path : String) -> String? {
  self.contents.get(path)
}

///|
pub fn Files::opened(self : Files) -> String? {
  self.open_file
}

///|
pub fn Files::same_contents(self : Files, other : Files) -> Bool {
  self.contents == other.contents
}

///|
pub fn Files::open(self : Files, path : String) -> Files raise {
  if !self.contents.contains(path) {
    raise @config.Invalid("Unknown workspace file: " + path)
  }
  let opened = { ..self, open_file: Some(path), }
  {
    ..opened,
    selected_project: opened.current() catch {
      _ => self.selected_project
    },
  }
}

///|
pub fn Files::write(self : Files, path : String, text : String) -> Files raise {
  let files = self.contents.copy()
  files[path] = text
  Files::new(
    files,
    open_file=self.open_file,
    current_project=self.selected_project,
  )
}

///|
pub fn Files::remove(self : Files, path : String) -> Files raise {
  let files = self.contents.copy()
  files.remove(path)
  Files::new(
    files,
    current_project=self.selected_project,
    open_file=if self.open_file == Some(path) { None } else { self.open_file },
  )
}

///|
pub fn Files::discover(self : Files) -> @discovery.Workspace raise {
  if !@discovery.primary_paths("").any(path => self.contents.contains(path)) &&
    !self.contents.contains("morphir.json") &&
    !self.contents.contains("morphir-workspace.json") {
    raise @config.Invalid(
      "The workspace needs a morphir.toml or morphir.json configuration file",
    )
  }
  @discovery.discover(self.tree())
}

///|
/// A project path, independent of language. Invalid projects remain visible through discovery diagnostics.
pub fn Files::current(self : Files) -> @discovery.ProjectPath? raise {
  let workspace = self.discover()
  let owners = match self.open_file {
    Some(path) =>
      if path == @discovery.join(workspace.root, "worksheet.scm") ||
        @discovery.within(@discovery.join(workspace.root, "models"), path) {
        []
      } else {
        workspace.projects.filter(p => @discovery.within(p.root, path))
      }
    None => []
  }
  owners.sort_by(fn(a, b) { b.root.length().compare(a.root.length()) })
  let project = match owners.get(0) {
    Some(owner) => Some(owner)
    None => {
      let selected = self.selected_project.bind(path => {
        workspace.projects
        .iter()
        .find_first(p => {
          p.root ==
          (@discovery.join(workspace.root, path.to_string()) catch { _ => "" })
        })
      })
      if selected is Some(project) {
        return Some(
          @discovery.ProjectPath::parse(
            if workspace.root == "" {
              project.root
            } else if project.root == workspace.root {
              ""
            } else {
              project.root[workspace.root.length() + 1:].to_owned()
            },
          ),
        )
      }
      let default_member = workspace.document.text(
        "workspace.default_member", "",
      )
      let default_root = @discovery.join(workspace.root, default_member)
      match workspace.projects.iter().find_first(p => p.root == default_root) {
        Some(project) => Some(project)
        None =>
          match
            workspace.projects.iter().find_first(p => p.root == workspace.root) {
            Some(project) => Some(project)
            None => workspace.projects.get(0)
          }
      }
    }
  }
  project.map(p => {
    @discovery.ProjectPath::parse(
      if p.root == workspace.root {
        ""
      } else if workspace.root == "" {
        p.root
      } else {
        p.root[workspace.root.length() + 1:].to_owned()
      },
    )
  })
}

///|
pub fn Files::apply(self : Files, edit : @discovery.Edit) -> Files raise {
  let tree = edit.apply(self.tree())
  Files::new(
    tree.files,
    current_project=self.selected_project,
    open_file=match self.open_file {
      Some(path) if tree.files.contains(path) => Some(path)
      _ => None
    },
  )
}

///|
pub fn Files::add_project(
  self : Files,
  path : @discovery.ProjectPath,
  project : @discovery.NewProject,
) -> Files raise {
  self.apply(
    @discovery.add_project(self.discover(), self.tree(), path, project),
  )
}

///|
pub fn Files::remove_project(
  self : Files,
  path : @discovery.ProjectPath,
  delete_files~ : Bool = false,
) -> Files raise {
  self.apply(
    @discovery.remove_project(self.discover(), self.tree(), path, delete_files~),
  )
}

///|
pub fn Files::to_json(self : Files) -> Json {
  {
    "version": 1,
    "files": Json::object(self.contents.map(fn(_, text) { Json::string(text) })),
    "openFile": self.open_file.map(Json::string).unwrap_or(Json::null()),
    "currentProject": self.selected_project
    .map(path => Json::string(path.to_string()))
    .unwrap_or(Json::null()),
  }
}

///|
pub fn Files::from_json(value : Json) -> Files raise {
  guard value is Object(fields) &&
    fields.get("version") == Some(Json::number(1)) &&
    fields.get("files") is Some(Object(entries)) else {
    raise @config.Invalid("Unsupported saved workspace file tree")
  }
  let files : Map[String, String] = Map([])
  for path, value in entries {
    guard value is String(text) else {
      raise @config.Invalid("Workspace file must be text: " + path)
    }
    files[path] = text
  }
  let open_file = match fields.get("openFile") {
    Some(String(path)) => Some(path)
    None | Some(Null) => None
    _ => raise @config.Invalid("Invalid saved open file")
  }
  let current_project = match fields.get("currentProject") {
    Some(String(path)) => Some(@discovery.ProjectPath::parse(path))
    None | Some(Null) => None
    _ => raise @config.Invalid("Invalid saved current project")
  }
  Files::new(files, open_file~, current_project~)
}

///|
/// Per-file records are written first. The manifest is the commit point, so an interrupted save
/// leaves the previous file generation readable. Old language-project keys are retired only after success.
pub fn Files::save(
  self : Files,
  prefix : String,
  generation : String,
  read : (String) -> String?,
  write : (String, String) -> Bool,
) -> Bool {
  let keys : Map[String, String] = Map([])
  for i, path in self.paths() {
    let key = prefix + ".files." + generation + "." + i.to_string()
    if read(key) is Some(_) {
      return false
    }
    keys[path] = key
  }
  for path, key in keys {
    if !write(key, Json::string(self.contents[path]).stringify()) {
      return false
    }
  }
  write(
    prefix + ".tree.v1",
    (
      {
        "version": 1,
        "files": Json::object(keys.map(fn(_, key) { Json::string(key) })),
        "openFile": self.open_file.map(Json::string).unwrap_or(Json::null()),
        "currentProject": self.selected_project
        .map(path => Json::string(path.to_string()))
        .unwrap_or(Json::null()),
      } : Json).stringify(),
  )
}

///|
pub fn load(prefix : String, read : (String) -> String?) -> Files? raise {
  guard read(prefix + ".tree.v1") is Some(manifest) else { return None }
  guard @json.parse(manifest) is Object(fields) &&
    fields.get("version") == Some(Json::number(1)) &&
    fields.get("files") is Some(Object(entries)) else {
    raise @config.Invalid("Invalid saved workspace manifest")
  }
  let contents : Map[String, Json] = Map([])
  for path, value in entries {
    guard value is String(key) && key.has_prefix(prefix + ".files.") else {
      raise @config.Invalid("Invalid workspace file record: " + path)
    }
    guard read(key) is Some(record) else {
      raise @config.Invalid("Missing workspace file record: " + path)
    }
    guard @json.parse(record) is String(text) else {
      raise @config.Invalid("Invalid workspace file record: " + path)
    }
    contents[path] = Json::string(text)
  }
  Some(
    Files::from_json({
      "version": 1,
      "files": Json::object(contents),
      "openFile": fields.get("openFile").unwrap_or(Json::null()),
      "currentProject": fields.get("currentProject").unwrap_or(Json::null()),
    }),
  )
}
