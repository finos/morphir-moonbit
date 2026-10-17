///|
pub(all) suberror DocError {
  DocError(String)
}

///|
pub(all) enum Expect {
  Value(String)
  Fails(String)
  Runs
} derive(Eq, Debug)

///|
pub(all) struct Example {
  files : Array[(String, String)]
  expect : Expect
  line : Int32
} derive(Eq, Debug)

///|
pub(all) struct Chapter {
  examples : Array[Example]
  skipped : Int32
  procedures : Array[String]
}

///|
fn strip_cr(line : String) -> String {
  if line.has_suffix("\r") {
    line[:line.length() - 1].to_owned()
  } else {
    line
  }
}

///|
/// The expectation of a block: its last non-empty line.
fn expectation(body : Array[String]) -> Expect {
  let mut i = body.length() - 1
  while i >= 0 && body[i] == "" {
    i -= 1
  }
  if i < 0 {
    return Runs
  }
  let last = body[i]
  if last.has_prefix(";; => ") {
    Value(last[6:].to_owned())
  } else if last.has_prefix(";; error: ") {
    Fails(last[10:].to_owned())
  } else {
    Runs
  }
}

///|
/// The line without its leading spaces and tabs.
fn without_indent(line : String) -> String {
  let mut i = 0
  while i < line.length() &&
        (
          line.code_unit_at(i).to_int() == 32 ||
          line.code_unit_at(i).to_int() == 9
        ) {
    i += 1
  }
  line[i:].to_owned()
}

///|
/// Whether the next ```scheme block at or after line index `from` starts with `;; file:`.
fn next_scheme_block_is_file(lines : Array[String], from : Int32) -> Bool {
  for j in from..<lines.length() {
    if lines[j] == "```scheme" {
      return j + 1 < lines.length() && lines[j + 1].has_prefix(";; file: ")
    }
  }
  false
}

///|
fn first_code(line : String) -> String? {
  guard line.find("`") is Some(start) else { return None }
  let rest = line[start + 1:].to_owned()
  guard rest.find("`") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
/// Turns the files gathered so far into one example and starts a new project.
fn close_project(
  examples : Array[Example],
  project : Array[(String, String)],
  expect : Expect,
  line : Int32,
) -> Unit {
  if !project.is_empty() {
    examples.push({ files: project.copy(), expect, line, })
    project.clear()
  }
}

///|
pub fn parse_chapter(text : String) -> Chapter raise DocError {
  let lines : Array[String] = []
  for l in text.split("\n") {
    lines.push(strip_cr(l.to_owned()))
  }
  let examples : Array[Example] = []
  let procedures : Array[String] = []
  // The line, counted from 1, where each procedure was first documented.
  let documented_on : Map[String, Int32] = Map([])
  let mut skipped = 0
  let mut in_procedures = false
  // A project of `;; file:` blocks that is still open: its files and the line of its first block.
  let project : Array[(String, String)] = []
  let mut project_line = 0
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if line.has_prefix("## ") {
      in_procedures = line == "## Built-in procedures"
    } else if in_procedures && line.has_prefix("| `") {
      if first_code(line) is Some(name) {
        // Any table row under the heading that starts with code names a procedure, so a repeat is an error.
        if documented_on.get(name) is Some(first) {
          raise DocError(
            "line \{i + 1}: procedure `\{name}` is already documented on line \{first}",
          )
        }
        documented_on[name] = i + 1
        procedures.push(name)
      }
    }
    if !line.has_prefix("```") &&
      without_indent(line).to_lower().has_prefix("```scheme") {
      raise DocError("line \{i + 1}: indented scheme block")
    }
    if line.has_prefix("```") {
      let open_line = i + 1
      let info : Array[String] = []
      for w in line[3:].to_owned().replace_all(old="\t", new=" ").split(" ") {
        if w.length() > 0 {
          info.push(w.to_owned())
        }
      }
      // Every scheme block is an example: refuse a fence that only looks like one.
      if info.length() > 0 {
        if info[0] != "scheme" && info[0].to_lower() == "scheme" {
          raise DocError(
            "line \{open_line}: scheme fence must be spelled `scheme`, found `\{info[0]}`",
          )
        }
        if info[0] == "scheme" &&
          !(info.length() == 1 || (info.length() == 2 && info[1] == "notest")) {
          let rest = info[1:].to_owned().join(" ")
          raise DocError(
            "line \{open_line}: unexpected text after `scheme`: `\{rest}`; use `scheme` or `scheme notest`",
          )
        }
      }
      let body : Array[String] = []
      i += 1
      while i < lines.length() && !lines[i].has_prefix("```") {
        body.push(lines[i])
        i += 1
      }
      if i == lines.length() {
        raise DocError("line \{open_line}: unclosed code block")
      }
      match info {
        ["scheme"] => {
          let expect = expectation(body)
          let source = body.join("\n")
          if body.length() > 0 && body[0].has_prefix(";; file: ") {
            if project.is_empty() {
              project_line = open_line
            }
            project.push((body[0][9:].to_owned(), source))
            if !(expect is Runs) {
              if next_scheme_block_is_file(lines, i + 1) {
                raise DocError(
                  "line \{project_line}: only the last file: block of a project may state an expectation",
                )
              }
              close_project(examples, project, expect, project_line)
            }
          } else {
            close_project(examples, project, Runs, project_line)
            examples.push({ files: [("", source)], expect, line: open_line, })
          }
        }
        ["scheme", "notest"] => skipped += 1
        _ => ()
      }
    }
    i += 1
  }
  close_project(examples, project, Runs, project_line)
  { examples, skipped, procedures, }
}
