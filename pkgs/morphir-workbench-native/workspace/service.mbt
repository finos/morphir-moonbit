///|
priv struct Project {
  id : String
  name : String
  path : String
  format : String
  error : String
}

///|
pub struct Service {
  priv mut root : Root?
  priv mut snapshot : Snapshot?
  priv mut projects : Array[Project]
  priv mut generation : Int32
  priv mut chooser : Int32?
  priv mut grant : String
  priv mut capture : Bytes?
  priv mut offset : Int32
  priv mut closed : Bool
}

///|
pub fn Service::new() -> Service {
  {
    root: None,
    snapshot: None,
    projects: [],
    generation: 0,
    chooser: None,
    grant: "",
    capture: None,
    offset: 0,
    closed: false,
  }
}

///|
pub fn Service::revoke(self : Service) -> Unit {
  if self.root is Some(root) {
    root.close()
  }
  self.root = None
  self.snapshot = None
  self.projects = []
  self.grant = ""
  self.capture = None
  self.chooser = None
}

///|
pub fn Service::close(self : Service) -> Unit {
  self.revoke()
  self.closed = true
}

///|
pub fn Service::begin_choose(self : Service) -> Int32 raise Invalid {
  guard !self.closed else { raise Rejected("workbench.workspace_revoked") }
  guard self.chooser == None else {
    raise Rejected("workbench.workspace_picker_busy")
  }
  guard self.generation < 2147483647 else {
    raise Rejected("workbench.workspace_quota")
  }
  self.generation += 1
  self.chooser = Some(self.generation)
  self.generation
}

///|
pub fn Service::cancel_choose(self : Service) -> Unit {
  self.chooser = None
}

///|
fn format(path : String) -> String? {
  if path.has_suffix(".json") {
    Some("morphir-json")
  } else if path.has_suffix(".ion") || path.has_suffix(".10n") {
    Some("ion-text")
  } else if path.has_suffix(".ionb") {
    Some("ion-binary")
  } else {
    None
  }
}

///|
fn candidates(
  workspace : @engine.Workspace,
  project : @engine.Project,
  files : Array[String],
) -> Array[String] raise {
  let out = @engine.join(
    workspace.root,
    workspace.document.text("workspace.out_dir", ".morphir/out"),
  )
  let relative = if project.root == workspace.root {
    ""
  } else if workspace.root == "" {
    project.root
  } else {
    project.root[workspace.root.length() + 1:].to_owned()
  }
  let destination = @engine.join(@engine.join(out, relative), "compile.dest")
  let conventional = [
    "morphir-ir.json", "morphir-ir.ion", "morphir-ir.10n", "morphir-ir.ionb",
  ].map(name => @engine.join(project.root, name))
  files.filter(path => {
    conventional.contains(path) ||
    (@engine.within(destination, path) && format(path) != None)
  })
}

///|
/// Complete only after the caller has revalidated the page/session following
/// the asynchronous native picker. Renderer data cannot create this authority.
pub fn Service::finish_choose(
  self : Service,
  ticket : Int32,
  path : String?,
) -> Json raise {
  guard !self.closed && self.chooser == Some(ticket) else {
    raise Rejected("workbench.workspace_picker_stale")
  }
  self.chooser = None
  guard path is Some(path) else { return { "ok": true, "cancelled": true } }
  let root = Root::open(path)
  let mut retained = false
  defer (if !retained { root.close() })
  let snapshot = root.snapshot()
  let workspace = @engine.discover(snapshot.tree)
  guard workspace.projects.length() <= 128 else {
    raise Rejected("workbench.workspace_quota")
  }
  let projects : Array[Project] = []
  for project in workspace.projects {
    guard @utf8.encode(project.name[:]).length() <= 256 else {
      raise Rejected("workbench.workspace_quota")
    }
    let paths = candidates(workspace, project, snapshot.files)
    if paths.is_empty() || project.error != None {
      projects.push({
        id: "project-" + projects.length().to_string(),
        name: project.name,
        path: "",
        format: "",
        error: project.error.unwrap_or(
          "No saved model checkpoint. Compile the project before opening it here.",
        ),
      })
    } else {
      for path in paths {
        projects.push({
          id: "project-" + projects.length().to_string(),
          name: project.name +
          (if paths.length() > 1 { " · " + path } else { "" }),
          path,
          format: format(path).unwrap(),
          error: "",
        })
      }
    }
  }
  guard projects.length() <= 128 else {
    raise Rejected("workbench.workspace_quota")
  }
  let grant = "workspace-" + ticket.to_string()
  let reply : Json = {
    "ok": true,
    "cancelled": false,
    "grantId": grant,
    "projects": projects.map(p => {
      (
        {
          "id": p.id,
          "name": p.name,
          "available": p.error == "",
          "message": p.error,
        } : Json)
    }),
    "warnings": workspace.warnings,
  }
  guard @utf8.encode(reply.stringify()[:]).length() <= 512 * 1024 else {
    raise Rejected("workbench.workspace_quota")
  }
  self.revoke()
  self.root = Some(root)
  self.snapshot = Some(snapshot)
  self.projects = projects
  self.grant = grant
  retained = true
  reply
}

///|
fn string(fields : Map[String, Json], key : String) -> String raise Invalid {
  match fields.get(key) {
    Some(String(s)) => s
    _ => raise Rejected("workbench.workspace_request")
  }
}

///|
pub fn Service::request(self : Service, source : String) -> Json {
  try {
    guard @utf8.encode(source[:]).length() <= 4096 else {
      raise Rejected("workbench.workspace_request")
    }
    guard @jobs.decode(source) is Object(fields) else {
      raise Rejected("workbench.workspace_request")
    }
    let action = string(fields, "action")
    if action == "cancel-picker" {
      guard fields.length() == 1 else {
        raise Rejected("workbench.workspace_request")
      }
      self.cancel_choose()
      return { "ok": true }
    }
    guard !self.closed &&
      self.root is Some(root) &&
      string(fields, "grantId") == self.grant else {
      raise Rejected("workbench.workspace_revoked")
    }
    if action == "release" {
      guard fields.length() == 2 else {
        raise Rejected("workbench.workspace_request")
      }
      self.capture = None
      return { "ok": true }
    }
    if action == "revoke" {
      guard fields.length() == 2 else {
        raise Rejected("workbench.workspace_request")
      }
      self.revoke()
      return { "ok": true }
    }
    root.current()
    if action == "open" {
      guard fields.length() == 3 else {
        raise Rejected("workbench.workspace_request")
      }
      guard self.capture == None else {
        raise Rejected("workbench.workspace_busy")
      }
      let project_id = string(fields, "projectId")
      guard self.projects.filter(p => p.id == project_id).get(0)
        is Some(project) else {
        raise Rejected("workbench.workspace_project")
      }
      guard project.error == "" else {
        raise Rejected("workbench.workspace_model_missing")
      }
      let fresh = root.snapshot()
      guard self.snapshot is Some(old) && fresh.tree.files == old.tree.files else {
        raise Rejected("workbench.workspace_changed")
      }
      let bytes = root.read(project.path)
      self.capture = Some(bytes)
      self.offset = 0
      return {
        "ok": true,
        "size": bytes.length(),
        "format": project.format,
        "filename": project.path.split("/").last().unwrap().to_owned(),
      }
    }
    if action == "read" {
      guard fields.length() == 3 &&
        fields.get("offset") is Some(Number(n, ..)) &&
        n == self.offset.to_double() else {
        raise Rejected("workbench.workspace_sequence")
      }
      guard self.capture is Some(bytes) else {
        raise Rejected("workbench.workspace_capture")
      }
      let start = self.offset
      let end = if bytes.length() < start + 192 * 1024 {
        bytes.length()
      } else {
        start + 192 * 1024
      }
      self.offset = end
      return {
        "ok": true,
        "offset": start,
        "content": @base64.encode(bytes[start:end]),
        "done": end == bytes.length(),
      }
    }
    raise Rejected("workbench.workspace_request")
  } catch {
    error => failure(error)
  }
}

///|
pub fn bridge_request(source : String) -> (String, String) raise {
  guard @utf8.encode(source[:]).length() <= 8192 else {
    raise Rejected("workbench.workspace_request")
  }
  guard @jobs.decode(source) is Object(fields) && fields.length() == 2 else {
    raise Rejected("workbench.workspace_request")
  }
  let id = string(fields, "sessionId")
  let body = string(fields, "body")
  guard id.length() <= 128 && @utf8.encode(body[:]).length() <= 4096 else {
    raise Rejected("workbench.workspace_request")
  }
  (id, body)
}

///|
pub fn failure(error : Error) -> Json {
  {
    "ok": false,
    "code": match error {
      Rejected(code) => code
      _ => "workbench.workspace_configuration"
    },
  }
}
