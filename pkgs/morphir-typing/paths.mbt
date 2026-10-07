// The logical path grammar. A path names one `Value` or `Pattern` node of a declaration. Plan 2 moves this
// grammar to `finos/morphir-ir/identities`.
//
// | Child                     | Step                                                  |
// | ------------------------- | ----------------------------------------------------- |
// | a declaration's body      | `/body`                                               |
// | `Apply` function          | `/function`                                           |
// | `Apply` argument          | `/argument`                                           |
// | `Lambda`                  | `/pattern`, `/body`                                   |
// | `LetDefinition`           | `/definition/body`, `/in`                             |
// | `LetRecursion`            | `/definitions/<name>/body`, `/in`                     |
// | `Destructure`             | `/pattern`, `/value`, `/in`                           |
// | `IfThenElse`              | `/condition`, `/then`, `/else`                        |
// | `PatternMatch`            | `/subject`, `/cases/<i>/pattern`, `/cases/<i>/body`   |
// | `Tuple`, `List`           | `/items/<i>`                                          |
// | `Record`                  | `/fields/<name>`                                      |
// | `Field`                   | `/record`                                             |
// | `UpdateRecord`            | `/record`, `/fields/<name>`                           |
// | `AsPattern`               | `/pattern`                                            |
// | `TuplePattern`            | `/items/<i>`                                          |
// | `ConstructorPattern`      | `/args/<i>`                                           |
// | `HeadTailPattern`         | `/head`, `/tail`                                      |
//
// A declaration's root is `value:<package>:<module>#<name>`. `<name>` is a canonical name and `<i>` is a
// 0-based index.

///|
/// The root path of the value declaration `name`.
fn value_root(name : @ir.FQName) -> String {
  "value:" + name.to_canonical()
}

///|
fn step(path : String, child : String) -> String {
  path + "/" + child
}

///|
/// The body of a declaration, a lambda or a definition.
fn path_body(path : String) -> String {
  step(path, "body")
}

///|
fn path_function(path : String) -> String {
  step(path, "function")
}

///|
fn path_argument(path : String) -> String {
  step(path, "argument")
}

///|
/// The pattern of a `Lambda`, a `Destructure` or an `AsPattern`.
fn path_pattern(path : String) -> String {
  step(path, "pattern")
}

///|
/// The definition of a `LetDefinition`. Its body is at `path_body` of this path.
fn path_definition(path : String) -> String {
  step(path, "definition")
}

///|
/// One definition of a `LetRecursion`. Its body is at `path_body` of this path.
fn path_definitions(path : String, name : @ir.Name) -> String {
  step(path, "definitions/" + name.to_canonical())
}

///|
fn path_definitions_body(path : String, name : @ir.Name) -> String {
  path_body(path_definitions(path, name))
}

///|
fn path_in(path : String) -> String {
  step(path, "in")
}

///|
fn path_value(path : String) -> String {
  step(path, "value")
}

///|
fn path_condition(path : String) -> String {
  step(path, "condition")
}

///|
fn path_then(path : String) -> String {
  step(path, "then")
}

///|
fn path_else(path : String) -> String {
  step(path, "else")
}

///|
fn path_subject(path : String) -> String {
  step(path, "subject")
}

///|
fn path_case_pattern(path : String, i : Int) -> String {
  step(path, "cases/\{i}/pattern")
}

///|
fn path_case_body(path : String, i : Int) -> String {
  step(path, "cases/\{i}/body")
}

///|
/// An item of a `Tuple`, a `List` or a `TuplePattern`.
fn path_item(path : String, i : Int) -> String {
  step(path, "items/\{i}")
}

///|
/// A field of a `Record` or an `UpdateRecord`.
fn path_field(path : String, name : @ir.Name) -> String {
  step(path, "fields/" + name.to_canonical())
}

///|
/// The record of a `Field` or an `UpdateRecord`.
fn path_record(path : String) -> String {
  step(path, "record")
}

///|
fn path_arg(path : String, i : Int) -> String {
  step(path, "args/\{i}")
}

///|
fn path_head(path : String) -> String {
  step(path, "head")
}

///|
fn path_tail(path : String) -> String {
  step(path, "tail")
}
