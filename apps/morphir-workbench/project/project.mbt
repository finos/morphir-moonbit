///|
/// One file of a project, with its path relative to the project root (for example `src/Shop/Orders/Api.elm`).
pub(all) struct ProjectFile {
  path : @ids.SourcePath
  content : String
} derive(Eq, Debug)

///|
/// How many files a language's project holds in the workbench. Per-file languages hold one
/// (`morphir-ukvn.5.22.14`).
pub(all) enum Layout {
  OneFile
  ManyFiles
} derive(Eq, Debug)

///|
/// The file rules of a language, from the catalog: its extensions and its layout.
pub(all) struct FileRules {
  extensions : Array[@ids.FileExtension]
  layout : Layout
}

///|
/// A refused edit: a code and a message for the person.
pub(all) suberror ProjectError {
  ProjectError(String, String)
}

///|
/// The open project of one language. `name` keeps the configuration spelling; `active` is the file in the editor.
pub(all) struct Project {
  name : @ids.SourcePackageName
  language : @ids.LanguageId
  provider : @ids.ProviderId?
  profile : @ids.ProfileId?
  files : Array[ProjectFile]
  exposed : Array[@ids.SourceModuleName]
  active : @ids.SourcePath
} derive(Eq, Debug)

///|
pub fn Project::single(
  language : @ids.LanguageId,
  name : @ids.SourcePackageName,
  path : @ids.SourcePath,
  content : String,
  provider~ : @ids.ProviderId? = None,
  profile~ : @ids.ProfileId? = None,
  exposed~ : Array[@ids.SourceModuleName] = [],
) -> Project {
  {
    name,
    language,
    provider,
    profile,
    files: [{ path, content, }],
    exposed,
    active: path,
  }
}

///|
pub fn Project::active_file(self : Project) -> ProjectFile {
  match self.files.search_by(f => f.path == self.active) {
    Some(i) => self.files[i]
    None => self.files[0]
  }
}

///|
/// The module name of a source file: the path under `src/` without its extension, with `.` between segments.
pub fn module_of(path : @ids.SourcePath) -> String? {
  let text = path.to_string()
  guard text.strip_prefix("src/") is Some(rest) else { return None }
  let rest = rest.to_owned()
  guard rest.rev_find(".") is Some(dot) else { return None }
  Some(rest.unsafe_substring(start=0, end=dot).replace_all(old="/", new="."))
}

///|
/// The module of `path` relative to the package: `src/Shop/Orders/Api.elm` in `Shop.Orders` gives `Api`.
fn Project::relative_module(self : Project, path : @ids.SourcePath) -> String? {
  guard module_of(path) is Some(full) else { return None }
  let prefix = self.name.to_string().replace_all(old="/", new=".") + "."
  match full.strip_prefix(prefix) {
    Some(rest) => Some(rest.to_owned())
    None => Some(full)
  }
}

///|
pub fn Project::modules(self : Project) -> Array[(@ids.SourceModuleName, Bool)] {
  self.files.filter_map(file => {
    match self.relative_module(file.path) {
      Some(text) =>
        try {
          let m = @ids.SourceModuleName::parse(text)
          Some((m, self.exposed.contains(m)))
        } catch {
          _ => None
        }
      None => None
    }
  })
}

///|
pub fn FileRules::add_reason(self : FileRules) -> String? {
  match self.layout {
    OneFile =>
      Some(
        "This language holds one file in the workbench; projects of several files are planned (morphir-ukvn.5.22.14)",
      )
    ManyFiles => None
  }
}

///|
fn Project::new_path(
  self : Project,
  rules : FileRules,
  text : String,
) -> @ids.SourcePath raise ProjectError {
  let path = @ids.SourcePath::parse(text) catch {
    _ =>
      raise ProjectError(
        "workbench.invalid_path",
        "Use a relative path with / between folders: " + text,
      )
  }
  if !text.has_prefix("src/") {
    raise ProjectError(
      "workbench.outside_source",
      "Put source files under src/: " + text,
    )
  }
  if !rules.extensions.iter().any(e => text.has_suffix(e.to_string())) {
    raise ProjectError(
      "workbench.wrong_extension",
      "Use one of " +
      rules.extensions.map(e => e.to_string()).join(", ") +
      ": " +
      text,
    )
  }
  if self.files.iter().any(f => f.path == path) {
    raise ProjectError(
      "workbench.duplicate_path",
      "A file with this path exists: " + text,
    )
  }
  path
}

///|
/// A new file is empty, except that an Elm file starts with its module header.
fn Project::starter(self : Project, path : @ids.SourcePath) -> String {
  if self.language.to_string() == "elm" && module_of(path) is Some(name) {
    "module " + name + " exposing (..)\n\n"
  } else {
    ""
  }
}

///|
pub fn Project::add_file(
  self : Project,
  rules : FileRules,
  path : String,
) -> Project raise ProjectError {
  if rules.add_reason() is Some(reason) {
    raise ProjectError("workbench.one_file_language", reason)
  }
  let path = self.new_path(rules, path)
  {
    ..self,
    files: self.files + [{ path, content: self.starter(path), }],
    active: path,
  }
}

///|
pub fn Project::rename_file(
  self : Project,
  rules : FileRules,
  from : @ids.SourcePath,
  to : String,
) -> Project raise ProjectError {
  guard self.files.search_by(f => f.path == from) is Some(index) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + from.to_string(),
    )
  }
  let path = self.new_path(rules, to)
  let files = self.files.copy()
  files[index] = { ..files[index], path, }
  let exposed = match (self.relative_module(from), self.relative_module(path)) {
    (Some(old), Some(new)) =>
      self.exposed.map(m => {
        if m.to_string() == old {
          @ids.SourceModuleName::parse(new) catch {
            _ => m
          }
        } else {
          m
        }
      })
    _ => self.exposed
  }
  {
    ..self,
    files,
    exposed,
    active: if self.active == from {
      path
    } else {
      self.active
    },
  }
}

///|
pub fn Project::delete_file(
  self : Project,
  path : @ids.SourcePath,
) -> Project raise ProjectError {
  guard self.files.iter().any(f => f.path == path) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + path.to_string(),
    )
  }
  if self.files.length() == 1 {
    raise ProjectError(
      "workbench.last_file", "A project keeps at least one file",
    )
  }
  let files = self.files.filter(f => f.path != path)
  let exposed = match self.relative_module(path) {
    Some(gone) => self.exposed.filter(m => m.to_string() != gone)
    None => self.exposed
  }
  {
    ..self,
    files,
    exposed,
    active: if self.active == path {
      files[0].path
    } else {
      self.active
    },
  }
}

///|
pub fn Project::set_content(
  self : Project,
  path : @ids.SourcePath,
  content : String,
) -> Project {
  {
    ..self,
    files: self.files.map(f => {
      if f.path == path {
        { ..f, content, }
      } else {
        f
      }
    }),
  }
}

///|
pub fn Project::set_active(
  self : Project,
  path : @ids.SourcePath,
) -> Project raise ProjectError {
  guard self.files.iter().any(f => f.path == path) else {
    raise ProjectError(
      "workbench.missing_file",
      "No file has this path: " + path.to_string(),
    )
  }
  { ..self, active: path, }
}

///|
/// A package name with letters, digits, `_`, `.`, `/` and `-` only, as the worker accepts.
pub fn Project::set_name(
  self : Project,
  text : String,
) -> Project raise ProjectError {
  let safe = text != "" &&
    text
    .to_array()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '/' ||
      c == '-'
    })
  let name : @ids.SourcePackageName? = if safe {
    Some(@ids.SourcePackageName::parse(text)) catch {
      _ => None
    }
  } else {
    None
  }
  match name {
    Some(name) => { ..self, name, }
    None =>
      raise ProjectError(
        "workbench.invalid_package",
        "Use letters, digits, _, ., / and - in the package name: " + text,
      )
  }
}

///|
pub fn Project::set_exposed(
  self : Project,
  module_name : @ids.SourceModuleName,
  exposed : Bool,
) -> Project {
  let others = self.exposed.filter(m => m != module_name)
  { ..self, exposed: if exposed { others + [module_name] } else { others }, }
}

///|
pub extend ProjectFile with Eq::{not_equal, equal}

///|
pub extend ProjectFile with @debug.Debug::{to_repr}

///|
pub extend Layout with Eq::{not_equal, equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
pub extend Project with Eq::{not_equal, equal}

///|
pub extend Project with @debug.Debug::{to_repr}
