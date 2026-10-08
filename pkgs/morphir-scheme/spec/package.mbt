///|
fn parse_forms(text : String) -> Array[@scheme.Located] raise SpecError {
  @scheme.parse_program_located(text) catch {
    @scheme.SchemeError::Syntax(message, offset) => {
      let (line, column) = @scheme.line_column(text, offset)
      raise SpecError(line~, column~, message~)
    }
    e => raise SpecError(line=1, column=1, message=e.to_string())
  }
}

///|
fn head_of(at : @scheme.Located) -> String? {
  match at.datum {
    Sequence(_, None) if !at.children.is_empty() => symbol(at.children[0])
    _ => None
  }
}

///|
fn read_path(
  ctx : Context,
  at : @scheme.Located,
  text : String,
  what : String,
) -> @ir.Path raise SpecError {
  let path = @ir.Path::parse(text) catch {
    _ => ctx.fail(at, "\{what} `\{text}` is not canonical")
  }
  if path.to_canonical() != text {
    ctx.fail(
      at,
      "\{what} `\{text}` is not canonical (use `\{path.to_canonical()}`)",
    )
  }
  path
}

///|
fn read_data(ctx : Context, at : @scheme.Located) -> @ir.Value raise SpecError {
  let attrs : @ir.ValueAttributes = @ir.ValueAttributes::default()
  match at.datum {
    Text(s) => @ir.Value::Literal(attrs, @ir.Literal::StringLiteral(s))
    Number(Integer(n)) =>
      @ir.Value::Literal(attrs, @ir.Literal::IntegerLiteral(n.to_string()))
    Boolean(b) => @ir.Value::Literal(attrs, @ir.Literal::BoolLiteral(b))
    Sequence(_, None) =>
      @ir.Value::List(attrs, at.children.map(c => read_data(ctx, c)))
    _ => ctx.fail(at, "annotation arguments are data")
  }
}

///|
fn read_annotation(
  ctx : Context,
  at : @scheme.Located,
) -> @ir.Annotation raise SpecError {
  if at.children.length() < 2 {
    ctx.fail(at, "an annotation is (annotation name arg...)")
  }
  let name_form = at.children[1]
  guard symbol(name_form) is Some(text) && text.contains("#") else {
    ctx.fail(name_form, "an annotation needs a qualified name")
  }
  let fq = read_reference(ctx, name_form, text)
  if at.children.length() == 2 {
    Compact(fq, None)
  } else {
    let args : Array[@ir.AnnotationArgument] = []
    for a in at.children[2:] {
      args.push(@ir.AnnotationArgument::Positional(read_data(ctx, a)))
    }
    Structured(fq, args)
  }
}

///|
fn read_doc(ctx : Context, at : @scheme.Located) -> String raise SpecError {
  guard at.children is [_, text_form] && text_form.datum is Text(text) else {
    ctx.fail(at, "a doc is (doc \"text\")")
  }
  text
}

///|
fn read_param(
  ctx : Context,
  at : @scheme.Located,
) -> (@ir.Name, @ir.Type) raise SpecError {
  guard at.children is [name_form, type_form] else {
    ctx.fail(at, "a parameter is (name type)")
  }
  (read_name(ctx, name_form), read_type(ctx, type_form))
}

///|
fn read_type_body(
  ctx : Context,
  at : @scheme.Located,
  params : Array[@ir.Name],
) -> @ir.TypeSpecificationBody raise SpecError {
  guard head_of(at) is Some(head) else { ctx.fail(at, "expected a type body") }
  check_head(ctx, at, head)
  let rest = at.children[1:].to_owned()
  match head {
    "opaque" => {
      if !rest.is_empty() {
        ctx.fail(at, "opaque takes no arguments")
      }
      OpaqueTypeSpecification(params)
    }
    "alias" => {
      guard rest is [target] else { ctx.fail(at, "alias takes one type") }
      TypeAliasSpecification(params, read_type(ctx, target))
    }
    "custom" => {
      let ctors : Map[@ir.Name, Array[(@ir.Name, @ir.Type)]] = Map([])
      for form in rest {
        if head_of(form) is None {
          ctx.fail(form, "a constructor is (name type...)")
        }
        let name = read_name(ctx, form.children[0])
        if ctors.contains(name) {
          ctx.fail(form, "duplicate constructor `\{name.to_canonical()}`")
        }
        let args : Array[(@ir.Name, @ir.Type)] = []
        for i, t in form.children[1:].to_owned() {
          let arg = @ir.Name::parse("arg-\{i + 1}") catch { _ => panic() }
          args.push((arg, read_type(ctx, t)))
        }
        ctors[name] = args
      }
      CustomTypeSpecification(params, ctors)
    }
    "derived" => {
      guard rest is [base, from_form, to_form] else {
        ctx.fail(at, "derived is (derived type from-name to-name)")
      }
      let reference = fn(form : @scheme.Located) -> @ir.FQName raise SpecError {
        guard symbol(form) is Some(text) && text.contains("#") else {
          ctx.fail(form, "expected a qualified name")
        }
        read_reference(ctx, form, text)
      }
      DerivedTypeSpecification(params, {
        base_type: read_type(ctx, base),
        from_base_type: reference(from_form),
        to_base_type: reference(to_form),
      })
    }
    _ => ctx.fail(at, "unknown type body `\{head}`")
  }
}

///|
fn read_module(
  ctx : Context,
  at : @scheme.Located,
) -> (@ir.Path, @ir.ModuleSpecification) raise SpecError {
  if at.children.length() < 2 {
    ctx.fail(at, "a module is (module name item...)")
  }
  let name_form = at.children[1]
  guard symbol(name_form) is Some(name_text) else {
    ctx.fail(name_form, "expected a module name")
  }
  let path = read_path(ctx, name_form, name_text, "module name")
  let types : Map[@ir.Name, @ir.Documented[@ir.TypeSpecification]] = Map([])
  let values : Map[@ir.Name, @ir.Documented[@ir.ValueSpecification]] = Map([])
  let mut doc : String? = None
  for i, item in at.children[2:].to_owned() {
    guard head_of(item) is Some(head) else {
      ctx.fail(item, "expected an item form")
    }
    check_head(ctx, item, head)
    match head {
      "doc" => {
        if i != 0 {
          ctx.fail(item, "a doc must be the first item")
        }
        doc = Some(read_doc(ctx, item))
      }
      "type" => {
        if item.children.length() < 3 {
          ctx.fail(item, "a type is (type name body param...)")
        }
        let name = read_name(ctx, item.children[1])
        if types.contains(name) {
          ctx.fail(item, "duplicate type `\{name.to_canonical()}`")
        }
        let mut next = 2
        let mut type_doc : String? = None
        if head_of(item.children[2]) is Some("doc") {
          type_doc = Some(read_doc(ctx, item.children[2]))
          next = 3
        }
        if item.children.length() <= next {
          ctx.fail(item, "a type is (type name body param...)")
        }
        let params : Array[@ir.Name] = []
        for p in item.children[next + 1:] {
          params.push(read_name(ctx, p))
        }
        let body = read_type_body(ctx, item.children[next], params)
        types[name] = { doc: type_doc, value: { annotations: [], body, }, }
      }
      "val" => {
        if item.children.length() < 4 {
          ctx.fail(item, "a val is (val name ((arg type)...) result item...)")
        }
        let name = read_name(ctx, item.children[1])
        if values.contains(name) {
          ctx.fail(item, "duplicate value `\{name.to_canonical()}`")
        }
        let params_form = item.children[2]
        if params_form.datum is Sequence(_, None) {

        } else {
          ctx.fail(params_form, "expected a parameter list")
        }
        let inputs = params_form.children.map(p => read_param(ctx, p))
        let output = read_type(ctx, item.children[3])
        let annotations : Array[@ir.Annotation] = []
        let mut val_doc : String? = None
        for j, extra in item.children[4:].to_owned() {
          guard head_of(extra) is Some(extra_head) else {
            ctx.fail(extra, "expected a doc or an annotation")
          }
          check_head(ctx, extra, extra_head)
          match extra_head {
            "doc" => {
              if j != 0 {
                ctx.fail(extra, "a doc must be the first item")
              }
              val_doc = Some(read_doc(ctx, extra))
            }
            "annotation" => annotations.push(read_annotation(ctx, extra))
            _ => ctx.fail(extra, "unknown item form `\{extra_head}`")
          }
        }
        values[name] = {
          doc: val_doc,
          value: { annotations, inputs, output, },
        }
      }
      _ => ctx.fail(item, "unknown item form `\{head}`")
    }
  }
  (path, { annotations: [], types, values, doc, })
}

///|
pub fn read_package(
  source : String,
) -> (@ir.PackageName, @ir.PackageSpecification) raise SpecError {
  let forms = parse_forms(source)
  let blank = { source, package_name: @ir.Path::from_names([]), }
  guard forms is [form] && head_of(form) is Some("package") else {
    if forms.is_empty() {
      raise SpecError(
        line=1,
        column=1,
        message="expected (package \"name\" module...)",
      )
    }
    blank.fail(forms[0], "expected (package \"name\" module...)")
  }
  let name_form = if form.children.length() > 1 {
    form.children[1]
  } else {
    form
  }
  guard name_form.datum is Text(name_text) else {
    blank.fail(name_form, "expected a package name")
  }
  let package_name = read_path(blank, name_form, name_text, "package name")
  let ctx = { source, package_name, }
  let modules : Map[@ir.Path, @ir.ModuleSpecification] = Map([])
  for m in form.children[2:].to_owned() {
    guard head_of(m) is Some(head) else {
      ctx.fail(m, "expected (module name item...)")
    }
    check_head(ctx, m, head)
    if head != "module" {
      ctx.fail(m, "expected (module name item...)")
    }
    let (path, spec) = read_module(ctx, m)
    if modules.contains(path) {
      ctx.fail(m, "duplicate module `\{path.to_canonical()}`")
    }
    modules[path] = spec
  }
  (package_name, { modules, })
}
