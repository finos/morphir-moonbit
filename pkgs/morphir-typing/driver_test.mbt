// Black-box tests for `infer`, `unknown_type` and `types_equivalent`. The specifications are small and made by
// hand with IR helpers; they do not use the real SDK.

///|
const INT = "morphir/SDK:basics#int"

///|
const BOOL = "morphir/SDK:basics#bool"

///|
const STRING = "morphir/SDK:string#string"

///|
const LIST = "morphir/SDK:list#list"

///|
fn nm(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => abort("bad name: \{text}")
  }
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => abort("bad FQName: \{text}")
  }
}

///|
fn pkg(text : String) -> @ir.Path {
  @ir.Path::parse(text) catch {
    _ => abort("bad path: \{text}")
  }
}

///|
fn tattrs() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn tv(text : String) -> @ir.Type {
  Variable(tattrs(), nm(text))
}

///|
fn tclass(text : String, class : String) -> @ir.Type {
  Variable(
    { ..tattrs(), constraints: Map([("typeclass", Text(class))]), },
    nm(text),
  )
}

///|
fn tmarked(text : String) -> @ir.Type {
  @typing.unknown_type(nm(text))
}

///|
fn tr(text : String, args : Array[@ir.Type]) -> @ir.Type {
  Reference(tattrs(), fq(text), args)
}

///|
fn tfn(a : @ir.Type, b : @ir.Type) -> @ir.Type {
  Function(tattrs(), a, b)
}

///|
fn t_int() -> @ir.Type {
  tr(INT, [])
}

///|
fn t_string() -> @ir.Type {
  tr(STRING, [])
}

///|
fn t_list(t : @ir.Type) -> @ir.Type {
  tr(LIST, [t])
}

///|
fn va() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn v_int(text : String) -> @ir.Value {
  Literal(va(), IntegerLiteral(text))
}

///|
fn v_str(s : String) -> @ir.Value {
  Literal(va(), StringLiteral(s))
}

///|
fn v_var(text : String) -> @ir.Value {
  Variable(va(), nm(text))
}

///|
fn v_ref(text : String) -> @ir.Value {
  Reference(va(), fq(text))
}

///|
fn v_apply(f : @ir.Value, args : Array[@ir.Value]) -> @ir.Value {
  let mut out = f
  for a in args {
    out = Apply(va(), out, a)
  }
  out
}

///|
fn v_lambda(p : @ir.Pattern, body : @ir.Value) -> @ir.Value {
  Lambda(va(), p, body)
}

///|
fn v_record(fields : Array[(String, @ir.Value)]) -> @ir.Value {
  Record(va(), Map::from_array(fields.map(f => (nm(f.0), f.1))))
}

///|
fn v_let(
  name : String,
  def : @ir.ValueDefinition,
  rest : @ir.Value,
) -> @ir.Value {
  LetDefinition(va(), nm(name), def, rest)
}

///|
fn p_var(text : String) -> @ir.Pattern {
  AsPattern(va(), WildcardPattern(va()), nm(text))
}

///|
fn p_wild() -> @ir.Pattern {
  WildcardPattern(va())
}

///|
fn opaque_type(params : Array[String]) -> @ir.Documented[@ir.TypeSpecification] {
  {
    doc: None,
    value: { annotations: [], body: OpaqueTypeSpecification(params.map(nm)), },
  }
}

///|
fn val_spec(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
) -> @ir.Documented[@ir.ValueSpecification] {
  {
    doc: None,
    value: { annotations: [], inputs: inputs.map(i => (nm(i.0), i.1)), output, },
  }
}

///|
fn module_spec(
  types : Array[(String, @ir.Documented[@ir.TypeSpecification])],
  values : Array[(String, @ir.Documented[@ir.ValueSpecification])],
) -> @ir.ModuleSpecification {
  {
    annotations: [],
    types: Map::from_array(types.map(t => (nm(t.0), t.1))),
    values: Map::from_array(values.map(v => (nm(v.0), v.1))),
    doc: None,
  }
}

///|
/// A tiny hand-made SDK: only what these tests need.
fn sdk() -> @ir.PackageSpecification {
  let add = val_spec([("a", tv("number")), ("b", tv("number"))], tv("number"))
  let lt = val_spec(
    [("a", tv("comparable")), ("b", tv("comparable"))],
    tr(BOOL, []),
  )
  let basics = module_spec(
    [
      ("int", opaque_type([])),
      ("float", opaque_type([])),
      ("bool", opaque_type([])),
    ],
    [("add", add), ("lt", lt)],
  )
  let string = module_spec([("string", opaque_type([]))], [
    ("length", val_spec([("s", t_string())], t_int())),
  ])
  {
    modules: Map([
      (pkg("basics"), basics),
      (pkg("string"), string),
      (pkg("list"), module_spec([("list", opaque_type(["a"]))], [])),
    ]),
  }
}

///|
fn deps() -> Map[@ir.PackageName, @ir.PackageSpecification] {
  Map([(pkg("morphir/SDK"), sdk())])
}

///|
fn def_of(
  name : String,
  def : @ir.ValueDefinition,
) -> (@ir.Name, @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]]) {
  (nm(name), { access: Public, value: { doc: None, value: def, }, })
}

///|
/// A library `acme/app` with the given modules and value definitions, in this order.
fn library(
  modules : Array[(String, Array[(String, @ir.ValueDefinition)])],
) -> @ir.IRFile {
  library_with_types(modules.map(m => (m.0, [], m.1)))
}

///|
fn library_with_types(
  modules : Array[
    (
      String,
      Array[(String, @ir.TypeDefinition)],
      Array[(String, @ir.ValueDefinition)],
    ),
  ],
) -> @ir.IRFile {
  let out : Map[@ir.ModuleName, @ir.AccessControlled[@ir.ModuleDefinition]] = Map([],
  )
  for m in modules {
    let types = Map::from_array(
      m.1.map(t => {
        let def : @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] = {
          access: Public,
          value: { doc: None, value: t.1, },
        }
        (nm(t.0), def)
      }),
    )
    let values = Map::from_array(m.2.map(v => def_of(v.0, v.1)))
    out[pkg(m.0)] = { access: Public, value: { types, values, doc: None, }, }
  }
  @ir.IRFile::new(Library(pkg("acme/app"), Map([]), { modules: out, })) catch {
    _ => abort("bad file")
  }
}

///|
fn fill(file : @ir.IRFile) -> @ir.IRFile raise @typing.InferenceFailed {
  @typing.infer(file, deps(), Fill)
}

///|
fn check(file : @ir.IRFile) -> @ir.IRFile raise @typing.InferenceFailed {
  @typing.infer(file, deps(), Check)
}

///|
/// The problems of a run that must fail, as `(code, node)` pairs.
fn problems(
  f : () -> @ir.IRFile raise @typing.InferenceFailed,
) -> Array[(String, String)] {
  failures(f).map(p => (p.code, p.node))
}

///|
fn failures(
  f : () -> @ir.IRFile raise @typing.InferenceFailed,
) -> Array[@typing.InferenceProblem] {
  try {
    f() |> ignore
    []
  } catch {
    InferenceFailed(ps) => ps
  }
}

///|
/// The definition of `module#name` in a library file.
fn definition_in(
  file : @ir.IRFile,
  module_ : String,
  name : String,
) -> @ir.ValueDefinition {
  guard file.distribution is Library(_, _, def) else { abort("not a library") }
  guard def.modules.get(pkg(module_)) is Some(m) else { abort("no module") }
  guard m.value.values.get(nm(name)) is Some(v) else { abort("no value") }
  v.value.value
}

///|
/// The signature `(inputs, output)` of `module#name` in a library file.
fn signature_in(
  file : @ir.IRFile,
  module_ : String,
  name : String,
) -> (Array[@ir.Type], @ir.Type) {
  guard definition_in(file, module_, name) is ExpressionBody(inputs, output, _) else {
    abort("not an expression body")
  }
  (inputs.map(i => i.1), output)
}

///|
/// Counts the value and pattern nodes of a file, and the nodes that have an `inferred_type`.
fn count_nodes(file : @ir.IRFile) -> (Int, Int) {
  guard file.distribution is Library(_, _, def) else { abort("not a library") }
  let counts = [0, 0]
  let visit = fn(a : @ir.ValueAttributes) {
    counts[0] = counts[0] + 1
    if a.inferred_type is Some(_) {
      counts[1] = counts[1] + 1
    }
  }
  for _, m in def.modules {
    for _, v in m.value.values {
      if v.value.value is ExpressionBody(_, _, body) {
        count_value(body, visit)
      }
    }
  }
  (counts[0], counts[1])
}

///|
fn count_value(v : @ir.Value, visit : (@ir.ValueAttributes) -> Unit) -> Unit {
  match v {
    Literal(a, _)
    | Constructor(a, _)
    | Variable(a, _)
    | Reference(a, _)
    | FieldFunction(a, _)
    | Unit(a)
    | Hole(a, _, _) => visit(a)
    Tuple(a, items) | List(a, items) => {
      visit(a)
      items.each(i => count_value(i, visit))
    }
    Record(a, fields) => {
      visit(a)
      fields.values().each(i => count_value(i, visit))
    }
    Field(a, r, _) => {
      visit(a)
      count_value(r, visit)
    }
    Apply(a, f, x) => {
      visit(a)
      count_value(f, visit)
      count_value(x, visit)
    }
    Lambda(a, p, body) => {
      visit(a)
      count_pattern(p, visit)
      count_value(body, visit)
    }
    LetDefinition(a, _, def, rest) => {
      visit(a)
      if def is ExpressionBody(_, _, body) {
        count_value(body, visit)
      }
      count_value(rest, visit)
    }
    LetRecursion(a, defs, rest) => {
      visit(a)
      for _, def in defs {
        if def is ExpressionBody(_, _, body) {
          count_value(body, visit)
        }
      }
      count_value(rest, visit)
    }
    Destructure(a, p, x, rest) => {
      visit(a)
      count_pattern(p, visit)
      count_value(x, visit)
      count_value(rest, visit)
    }
    IfThenElse(a, c, t, e) => {
      visit(a)
      [c, t, e].each(i => count_value(i, visit))
    }
    PatternMatch(a, s, cases) => {
      visit(a)
      count_value(s, visit)
      for c in cases {
        count_pattern(c.0, visit)
        count_value(c.1, visit)
      }
    }
    UpdateRecord(a, r, fields) => {
      visit(a)
      count_value(r, visit)
      fields.values().each(i => count_value(i, visit))
    }
  }
}

///|
fn count_pattern(
  p : @ir.Pattern,
  visit : (@ir.ValueAttributes) -> Unit,
) -> Unit {
  match p {
    WildcardPattern(a)
    | EmptyListPattern(a)
    | LiteralPattern(a, _)
    | UnitPattern(a) => visit(a)
    AsPattern(a, inner, _) => {
      visit(a)
      count_pattern(inner, visit)
    }
    TuplePattern(a, items) | ConstructorPattern(a, _, items) => {
      visit(a)
      items.each(i => count_pattern(i, visit))
    }
    HeadTailPattern(a, h, t) => {
      visit(a)
      count_pattern(h, visit)
      count_pattern(t, visit)
    }
  }
}

///|
/// `length xs = case xs of [] -> 0; _ :: rest -> 1 + length rest`, with an unknown signature.
fn length_def(self_name : String) -> @ir.ValueDefinition {
  let cases : Array[(@ir.Pattern, @ir.Value)] = [
    (EmptyListPattern(va()), v_int("0")),
    (
      HeadTailPattern(va(), p_wild(), p_var("rest")),
      v_apply(v_ref("morphir/SDK:basics#add"), [
        v_int("1"),
        v_apply(v_ref(self_name), [v_var("rest")]),
      ]),
    ),
  ]
  ExpressionBody(
    [(nm("xs"), tmarked("t"))],
    tmarked("r"),
    PatternMatch(va(), v_var("xs"), cases),
  )
}

///|
/// A two-module library with lets, lambdas, records, patterns and a cross-module reference.
fn sample_library() -> @ir.IRFile {
  let total = @ir.ValueDefinition::ExpressionBody(
    [(nm("n"), t_int())],
    t_int(),
    v_apply(v_ref("acme/app:b#double"), [
      v_let("y", ExpressionBody([], tmarked("t"), v_var("n")), v_var("y")),
    ]),
  )
  let pick = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_lambda(
      TuplePattern(va(), [p_var("p"), p_wild()]),
      Field(
        va(),
        v_record([("total", v_var("p")), ("name", v_str("x"))]),
        nm("total"),
      ),
    ),
  )
  let ident = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_let(
      "id",
      ExpressionBody([], tmarked("s"), v_lambda(p_var("x"), v_var("x"))),
      Tuple(va(), [
        v_apply(v_var("id"), [v_int("1")]),
        v_apply(v_var("id"), [v_str("s")]),
      ]),
    ),
  )
  let double = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:basics#add"), [v_var("x"), v_var("x")]),
  )
  library([
    ("a", [("total", total), ("pick", pick), ("ident", ident)]),
    ("b", [("double", double), ("length", length_def("acme/app:b#length"))]),
  ])
}

///|
test "1. fill sets inferred_type on every value and pattern node" {
  let file = sample_library()
  assert_eq(count_nodes(file).1, 0)
  let filled = fill(file)
  let (nodes, typed) = count_nodes(filled)
  assert_true(nodes > 30)
  assert_eq(typed, nodes)
  // The unknown signatures are solved.
  assert_eq(
    signature_in(filled, "b", "double"),
    ([tclass("number-a", "number")], tclass("number-a", "number")),
  )
  let (_, pick) = signature_in(filled, "a", "pick")
  assert_eq(pick, tfn(@ir.Type::Tuple(tattrs(), [tv("a"), tv("b")]), tv("a")))
  let (_, ident) = signature_in(filled, "a", "ident")
  assert_eq(
    ident,
    @ir.Type::Tuple(tattrs(), [tclass("number-a", "number"), t_string()]),
  )
}

///|
test "2. a module references a value of a later module (Review Focus)" {
  let use_ = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    Tuple(va(), [
      v_apply(v_ref("acme/app:b#f"), [v_int("1")]),
      v_apply(v_ref("acme/app:b#f"), [v_str("s")]),
    ]),
  )
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    v_var("x"),
  )
  let filled = fill(library([("a", [("use", use_)]), ("b", [("f", f)])]))
  // `f` is generalized before `use` is solved, so `use` takes it at two types.
  assert_eq(
    signature_in(filled, "a", "use").1,
    Tuple(tattrs(), [tclass("number-a", "number"), t_string()]),
  )
  assert_eq(signature_in(filled, "b", "f"), ([tv("a")], tv("a")))
}

///|
test "3. polymorphic recursion through an annotation (Review Focus)" {
  // f : List a -> Int
  // f xs = f [ xs ]
  let body = v_apply(v_ref("acme/app:m#f"), [List(va(), [v_var("xs")])])
  let declared = @ir.ValueDefinition::ExpressionBody(
    [(nm("xs"), t_list(tv("a")))],
    t_int(),
    body,
  )
  let file = library([("m", [("f", declared)])])
  let filled = fill(file)
  assert_eq(signature_in(filled, "m", "f"), ([t_list(tv("a"))], t_int()))
  // Without the annotation the recursion is monomorphic, and the type is infinite.
  let unknown = @ir.ValueDefinition::ExpressionBody(
    [(nm("xs"), tmarked("t"))],
    tmarked("r"),
    body,
  )
  assert_eq(problems(() => fill(library([("m", [("f", unknown)])]))), [
    ("occurs", "value:acme/app:m#f/body/argument"),
  ])
}

///|
test "4. an undeclared recursive function infers monomorphically" {
  let file = library([("m", [("length", length_def("acme/app:m#length"))])])
  let filled = fill(file)
  assert_eq(
    signature_in(filled, "m", "length"),
    ([t_list(tv("a"))], tclass("number-a", "number")),
  )
}

///|
test "5. a body that narrows an annotated variable is rigid_variable" {
  // id : a -> a
  // id = \x -> 1
  let id = @ir.ValueDefinition::ExpressionBody(
    [],
    tfn(tv("a"), tv("a")),
    v_lambda(p_var("x"), v_int("1")),
  )
  let found = failures(() => fill(library([("m", [("id", id)])])))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("rigid_variable", "value:acme/app:m#id/body"),
  ])
  assert_eq(
    found[0].message,
    "the variable `a` is annotated as any type, but the body needs number",
  )
}

///|
test "6. the unknown marker is solved: inc x = x + length \"s\" is Int -> Int" {
  let body = v_apply(v_ref("morphir/SDK:basics#add"), [
    v_var("x"),
    v_apply(v_ref("morphir/SDK:string#length"), [v_str("s")]),
  ])
  let inc = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("a"))],
    tmarked("b"),
    body,
  )
  let filled = fill(library([("m", [("inc", inc)])]))
  assert_eq(signature_in(filled, "m", "inc"), ([t_int()], t_int()))
}

///|
test "7. filling a filled file gives the same file (Review Focus)" {
  let once = fill(sample_library())
  let twice = fill(once)
  assert_eq(twice, once)
}

///|
test "8. check mode returns a correct file unchanged and reports a changed type" {
  let filled = fill(sample_library())
  assert_true(check(filled) == filled)
  // Change the type of the argument of `double` in `total`.
  guard filled.distribution is Library(name, own, def) else { fail("library") }
  guard def.modules.get(pkg("a")) is Some(a) else { fail("module a") }
  guard a.value.values.get(nm("total")) is Some(total) else { fail("total") }
  guard total.value.value
    is ExpressionBody(inputs, output, Apply(attrs, f, arg)) else {
    fail("total body")
  }
  let wrong : @ir.Value = match arg {
    LetDefinition(argument, n, d, rest) =>
      LetDefinition(
        { ..argument, inferred_type: Some(t_string()), },
        n,
        d,
        rest,
      )
    _ => fail("argument")
  }
  let values = a.value.values.copy()
  values[nm("total")] = {
    ..total,
    value: {
      ..total.value,
      value: ExpressionBody(inputs, output, Apply(attrs, f, wrong)),
    },
  }
  let modules = def.modules.copy()
  modules[pkg("a")] = { ..a, value: { ..a.value, values, }, }
  let changed = @ir.IRFile::new(Library(name, own, { modules, }))
  let found = failures(() => check(changed))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("annotation_mismatch", "value:acme/app:a#total/body/argument"),
  ])
  assert_eq(found[0].expected, Some(t_int()))
  assert_eq(found[0].found, Some(t_string()))
  // Fill reports the same disagreement.
  assert_eq(problems(() => fill(changed)), [
    ("annotation_mismatch", "value:acme/app:a#total/body/argument"),
  ])
}

///|
test "9. a failure in one component does not stop another" {
  // x-bad : Int
  // x-bad = "s"
  let loc : @ir.SourceLocation = {
    start_line: 3,
    start_column: 9,
    end_line: 3,
    end_column: 12,
  }
  let x_bad = @ir.ValueDefinition::ExpressionBody(
    [],
    t_int(),
    Literal({ ..va(), source: Some(loc), }, StringLiteral("s")),
  )
  let good = @ir.ValueDefinition::ExpressionBody([], tmarked("r"), v_int("1"))
  // a-bad : String
  // a-bad = { total = 1 }.count
  let a_bad = @ir.ValueDefinition::ExpressionBody(
    [],
    t_string(),
    Field(va(), v_record([("total", v_int("1"))]), nm("count")),
  )
  let file = library([
    ("m", [("x-bad", x_bad), ("good", good), ("a-bad", a_bad)]),
  ])
  let found = failures(() => fill(file))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("missing_field", "value:acme/app:m#a-bad/body"),
    ("type_mismatch", "value:acme/app:m#x-bad/body"),
  ])
  assert_eq(found[0].message, "the record has no field `count`")
  assert_eq(found[1].message, "expected Int, found String")
  assert_eq(found[1].expected, Some(t_int()))
  assert_eq(found[1].found, Some(t_string()))
  assert_eq(found[1].source, Some(loc))
  // Check mode collects the same problems.
  assert_eq(problems(() => check(file)), found.map(p => (p.code, p.node)))
}

///|
test "10. two runs give equal files" {
  assert_true(fill(sample_library()) == fill(sample_library()))
}

///|
test "11. types_equivalent renames variables bijectively" {
  assert_true(
    @typing.types_equivalent(tfn(tv("a"), tv("b")), tfn(tv("x"), tv("y"))),
  )
  assert_false(
    @typing.types_equivalent(tfn(tv("a"), tv("a")), tfn(tv("x"), tv("y"))),
  )
  assert_false(
    @typing.types_equivalent(tfn(tv("a"), tv("b")), tfn(tv("x"), tv("x"))),
  )
  // Attributes do not count.
  assert_true(
    @typing.types_equivalent(tclass("number-a", "number"), tmarked("n")),
  )
  assert_false(@typing.types_equivalent(t_int(), t_string()))
  assert_false(@typing.types_equivalent(t_list(tv("a")), tv("a")))
}

///|
test "unknown_type carries the unknown marker" {
  assert_eq(
    @typing.unknown_type(nm("a")),
    Variable(
      { ..tattrs(), extensions: Map([("morphir.inference", Text("unknown"))]), },
      nm("a"),
    ),
  )
}

///|
test "carry-forward: rigid classes do not leak between declarations" {
  // cmp : x -> x -> Bool, where x is comparable
  // cmp a b = lt a b
  let x = tclass("x", "comparable")
  let lt = v_ref("morphir/SDK:basics#lt")
  let cmp = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), x), (nm("b"), x)],
    tr(BOOL, []),
    v_apply(lt, [v_var("a"), v_var("b")]),
  )
  // bad : Int -> Bool
  // bad n = let h : x -> Bool
  //             h v = lt v v
  //         in h n
  // The `x` of the let annotation is a new rigid with no class, so `lt v v` fails.
  let h = @ir.ValueDefinition::ExpressionBody(
    [(nm("v"), tv("x"))],
    tr(BOOL, []),
    v_apply(lt, [v_var("v"), v_var("v")]),
  )
  let bad = @ir.ValueDefinition::ExpressionBody(
    [(nm("n"), t_int())],
    tr(BOOL, []),
    v_let("h", h, v_apply(v_var("h"), [v_var("n")])),
  )
  let at = "value:acme/app:m#bad/body/definition/body/function/argument"
  assert_eq(
    problems(() => fill(library([("m", [("cmp", cmp), ("bad", bad)])]))),
    [("rigid_variable", at)],
  )
  // A failed declaration does not leak its rigid classes either.
  let failing = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), x)],
    tr(BOOL, []),
    v_str("s"),
  )
  assert_eq(
    problems(() => fill(library([("m", [("failing", failing), ("bad", bad)])]))),
    [("rigid_variable", at), ("type_mismatch", "value:acme/app:m#failing/body")],
  )
}

///|
test "carry-forward: rigid classes do not leak inside one group" {
  // p and q refer to each other, so they are one group, solved in IR order.
  // p (a : x, where x is comparable) = q 1
  // q b = ( p, lt hole hole ), where the hole has the type x
  // The `x` of the hole is not p's `x`: it has no class, so `lt hole hole` fails.
  let p = @ir.ValueDefinition::ExpressionBody(
    [(nm("a"), tclass("x", "comparable"))],
    tmarked("r"),
    v_apply(v_ref("acme/app:m#q"), [v_int("1")]),
  )
  let hole : @ir.Value = Hole(va(), DeletedDuringRefactor("x"), Some(tv("x")))
  let q = @ir.ValueDefinition::ExpressionBody(
    [(nm("b"), tmarked("t"))],
    tmarked("r"),
    Tuple(va(), [
      v_ref("acme/app:m#p"),
      v_apply(v_ref("morphir/SDK:basics#lt"), [hole, hole]),
    ]),
  )
  assert_eq(problems(() => fill(library([("m", [("p", p), ("q", q)])]))), [
    ("rigid_variable", "value:acme/app:m#q/body/items/1/function/argument"),
  ])
}

///|
test "a failed group reports once, and its dependants do not report again" {
  // even n = ( odd n, String.length 1 ) and odd n = ( even n, String.length 1 ) are one group. Both bodies are
  // wrong, but the group stops at its first failure.
  let wrong = fn(other : String) -> @ir.ValueDefinition {
    ExpressionBody(
      [(nm("n"), tmarked("t"))],
      tmarked("r"),
      Tuple(va(), [
        v_apply(v_ref(other), [v_var("n")]),
        v_apply(v_ref("morphir/SDK:string#length"), [v_int("1")]),
      ]),
    )
  }
  let even = wrong("acme/app:m#odd")
  let odd = wrong("acme/app:m#even")
  // user = String.length (even 1): `even` failed, so it is any type here.
  let user = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_apply(v_ref("morphir/SDK:string#length"), [
      v_apply(v_ref("acme/app:m#even"), [v_int("1")]),
    ]),
  )
  let found = problems(() => {
    fill(library([("m", [("even", even), ("odd", odd), ("user", user)])]))
  })
  assert_eq(found, [
    ("no_instance", "value:acme/app:m#even/body/items/1/argument"),
  ])
}

///|
test "carry-forward: names do not clash with rigid names inside the body" {
  // f x = let g : a -> a = \y -> y in g x
  let g = @ir.ValueDefinition::ExpressionBody(
    [],
    tfn(tv("a"), tv("a")),
    v_lambda(p_var("y"), v_var("y")),
  )
  let body = v_let("g", g, v_apply(v_var("g"), [v_var("x")]))
  let f = @ir.ValueDefinition::ExpressionBody(
    [(nm("x"), tmarked("t"))],
    tmarked("r"),
    body,
  )
  let filled = fill(library([("m", [("f", f)])]))
  assert_eq(signature_in(filled, "m", "f"), ([tv("b")], tv("b")))
  assert_true(fill(filled) == filled)
}

///|
test "carry-forward: a cyclic alias is unsupported at its type path" {
  let loop_ : @ir.TypeDefinition = TypeAliasDefinition(
    [],
    tr("acme/app:m#loop", []),
  )
  let file = library_with_types([
    ("m", [("loop", loop_)], [("one", ExpressionBody([], t_int(), v_int("1")))]),
  ])
  let found = failures(() => fill(file))
  assert_eq(found.map(p => (p.code, p.node)), [
    ("unsupported", "type:acme/app:m#loop"),
  ])
  assert_eq(problems(() => check(file)), [
    ("unsupported", "type:acme/app:m#loop"),
  ])
}

///|
test "let signatures with unknown types are filled" {
  // f = let id : s? = \x -> x in id 1
  let id = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("s"),
    v_lambda(p_var("x"), v_var("x")),
  )
  let f = @ir.ValueDefinition::ExpressionBody(
    [],
    tmarked("r"),
    v_let("id", id, v_apply(v_var("id"), [v_int("1")])),
  )
  let filled = fill(library([("m", [("f", f)])]))
  guard definition_in(filled, "m", "f")
    is ExpressionBody(_, _, LetDefinition(_, _, ExpressionBody(_, out, _), _)) else {
    fail("let")
  }
  assert_eq(out, tfn(tv("a"), tv("a")))
}

///|
test "native and external bodies" {
  // n : Int -> Int is native. e : Int has a fallback that calls n. bad : Int has a String fallback.
  let native : @ir.ValueDefinition = NativeBody([(nm("x"), t_int())], t_int(), {
    hint: Arithmetic,
    description: None,
  })
  let external : @ir.ValueDefinition = ExternalBody(
    [],
    t_int(),
    [],
    Some(v_apply(v_ref("acme/app:m#n"), [v_int("1")])),
  )
  let bad : @ir.ValueDefinition = ExternalBody(
    [],
    t_int(),
    [],
    Some(v_str("s")),
  )
  let file = library([("m", [("n", native), ("e", external)])])
  let filled = fill(file)
  assert_eq(definition_in(filled, "m", "n"), native)
  guard definition_in(filled, "m", "e") is ExternalBody(_, _, _, Some(fallback)) else {
    fail("external")
  }
  guard fallback is Apply(attrs, _, _) else { fail("apply") }
  assert_eq(attrs.inferred_type, Some(t_int()))
  assert_eq(problems(() => fill(library([("m", [("bad", bad)])]))), [
    ("type_mismatch", "value:acme/app:m#bad/body"),
  ])
}

///|
test "specs: fill returns the file, check resolves references" {
  let spec : @ir.PackageSpecification = {
    modules: Map([
      (
        pkg("m"),
        module_spec([], [
          ("ok", val_spec([("x", t_int())], t_int())),
          ("bad", val_spec([], tr("acme/app:m#nothing", []))),
          ("far", val_spec([], tr("other/pkg:m#t", []))),
        ]),
      ),
    ]),
  }
  let file = @ir.IRFile::new(Specs(pkg("acme/app"), Map([]), spec))
  assert_true(fill(file) == file)
  assert_eq(problems(() => check(file)), [
    ("unknown_reference", "value:acme/app:m#bad"),
    ("missing_dependency", "value:acme/app:m#far"),
  ])
}

///|
test "an application is filled and keeps its entry points" {
  let main = @ir.ValueDefinition::ExpressionBody([], tmarked("r"), v_str("hi"))
  guard library([("m", [("main", main)])]).distribution is Library(name, _, def) else {
    fail("library")
  }
  let entries : Map[String, @ir.EntryPoint] = Map([
    ("main", { target: fq("acme/app:m#main"), kind: Main, doc: None, }),
  ])
  let file = @ir.IRFile::new(Application(name, Map([]), def, entries))
  let filled = fill(file)
  guard filled.distribution is Application(_, _, def, kept) else {
    fail("application")
  }
  assert_eq(kept, entries)
  guard def.modules.get(pkg("m")) is Some(m) else { fail("module") }
  guard m.value.values.get(nm("main")) is Some(v) else { fail("main") }
  guard v.value.value is ExpressionBody(_, output, body) else { fail("body") }
  assert_eq(output, t_string())
  guard body is Literal(attrs, _) else { fail("literal") }
  assert_eq(attrs.inferred_type, Some(t_string()))
}
