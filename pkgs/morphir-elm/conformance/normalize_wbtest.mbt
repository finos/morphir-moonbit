///|
fn library(
  modules : Map[@ir.Path, @ir.AccessControlled[@ir.ModuleDefinition]],
) -> @ir.IRFile {
  @ir.IRFile::new(
    Library(@ir.Path::parse("p") catch { _ => panic() }, Map([]), { modules, }),
  ) catch {
    _ => panic()
  }
}

///|
fn module_with(doc : String?) -> @ir.AccessControlled[@ir.ModuleDefinition] {
  { access: Public, value: { types: Map([]), values: Map([]), doc, }, }
}

///|
test "differences name the module and ignore an empty doc" {
  let m = @ir.Path::parse("m") catch { _ => panic() }
  let a = library(Map::from_array([(m, module_with(Some("")))]))
  let b = library(Map::from_array([(m, module_with(None))]))
  assert_eq(differences(a, b), [])
  let c = library(Map::from_array([(m, module_with(Some("x")))]))
  assert_eq(differences(a, c), ["module m: doc"])
  assert_eq(differences(a, library(Map([]))), ["module m: missing"])
}

///|
fn int_type(source : @ir.SourceLocation?) -> @ir.Type {
  Reference(
    { ..@ir.TypeAttributes::default(), source, },
    @ir.FQName::parse("morphir/SDK:basics#int") catch {
      _ => panic()
    },
    [],
  )
}

///|
fn module_of(
  types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ],
  values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ],
) -> @ir.IRFile {
  let m = @ir.Path::parse("m") catch { _ => panic() }
  library(
    Map::from_array([
      (m, { access: Public, value: { types, values, doc: None, }, }),
    ]),
  )
}

///|
test "differences compare value signatures, not bodies, and strip type attributes" {
  let f = @ir.Name::parse("f") catch { _ => panic() }
  let x = @ir.Name::parse("x") catch { _ => panic() }
  let t = @ir.Name::parse("t") catch { _ => panic() }
  let here : @ir.SourceLocation? = Some({
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 4,
  })
  let expected = module_of(
    Map::from_array([
      (
        t,
        {
          access: Public,
          value: {
            doc: Some(""),
            value: TypeAliasDefinition([], int_type(here)),
          },
        },
      ),
    ]),
    Map::from_array([
      (
        f,
        {
          access: Public,
          value: {
            doc: Some(""),
            value: ExpressionBody(
              [(x, int_type(here))],
              int_type(None),
              Unit(@ir.ValueAttributes::default()),
            ),
          },
        },
      ),
    ]),
  )
  let draft = fn(
    output : @ir.Type,
    access : @ir.Access,
  ) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
    {
      access,
      value: {
        doc: Some(""),
        value: IncompleteBody([(x, int_type(None))], Some(output), Draft, None),
      },
    }
  }
  let aliased = fn(
    target : @ir.Type,
  ) -> @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]] {
    {
      access: Public,
      value: { doc: Some(""), value: TypeAliasDefinition([], target), },
    }
  }
  let same = module_of(
    Map::from_array([(t, aliased(int_type(None)))]),
    Map::from_array([(f, draft(int_type(None), Public))]),
  )
  assert_eq(differences(expected, same), [])
  let unit_type : @ir.Type = Unit(@ir.TypeAttributes::default())
  let changed = module_of(
    Map::from_array([(t, aliased(unit_type))]),
    Map::from_array([(f, draft(unit_type, Private))]),
  )
  assert_eq(differences(expected, changed), [
    "type m#t: definition", "value m#f: access", "value m#f: output",
  ])
  let other = @ir.Name::parse("g") catch { _ => panic() }
  let renamed = module_of(
    Map([]),
    Map::from_array([(other, draft(int_type(None), Public))]),
  )
  assert_eq(differences(expected, renamed), [
    "type m#t: missing", "value m#f: missing", "value m#g: unexpected",
  ])
}
