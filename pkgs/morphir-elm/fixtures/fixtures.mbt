///|
fn t() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn v() -> @ir.ValueAttributes {
  { source: None, inferred_type: None, extensions: Map([]), }
}

///|
fn n(text : String) -> @ir.Name {
  @ir.Name::parse(text) catch {
    _ => panic()
  }
}

///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
fn ty(name : String, args? : Array[@ir.Type] = []) -> @ir.Type {
  Reference(t(), fq(name), args)
}

///|
fn call(f : String, args : Array[@ir.Value]) -> @ir.Value {
  args.fold(init=@ir.Value::Reference(v(), fq(f)), (acc, a) => {
    @ir.Value::Apply(v(), acc, a)
  })
}

///|
fn local(name : String) -> @ir.Value {
  Variable(v(), n(name))
}

///|
fn public_value(
  inputs : Array[(String, @ir.Type)],
  output : @ir.Type,
  body : @ir.Value,
  doc? : String? = None,
) -> @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] {
  {
    access: Public,
    value: {
      doc,
      value: ExpressionBody(inputs.map(i => (n(i.0), i.1)), output, body),
    },
  }
}

///|
fn library(
  package_name : String,
  modules : Array[(String, @ir.ModuleDefinition)],
) -> @ir.IRFile {
  @ir.IRFile::new(
    Library(@ir.Path::parse(package_name) catch { _ => panic() }, Map([]), {
      modules: Map::from_array(
        modules.map(m => {
          (
            @ir.Path::parse(m.0) catch {
              _ => panic()
            },
            { access: @ir.Access::Public, value: m.1, },
          )
        }),
      ),
    }),
  ) catch {
    _ => panic()
  }
}

///|
/// The rentals model of the v2 conformance fixture, in current IR.
pub fn rentals() -> @ir.IRFile {
  let int = ty("morphir/SDK:basics#int")
  let result = ty("morphir/SDK:result#result", args=[
    ty("morphir/SDK:string#string"),
    int,
  ])
  let body = @ir.Value::IfThenElse(
    v(),
    call("morphir/SDK:basics#less-than-or-equal", [
      local("requested-quantity"),
      local("availability"),
    ]),
    @ir.Value::Apply(
      v(),
      Constructor(v(), fq("morphir/SDK:result#ok")),
      local("requested-quantity"),
    ),
    @ir.Value::Apply(
      v(),
      Constructor(v(), fq("morphir/SDK:result#err")),
      Literal(v(), StringLiteral("Insufficient availability")),
    ),
  )
  library("morphir/example/app", [
    (
      "rentals",
      {
        types: Map([]),
        doc: Some("Rentals."),
        values: Map::from_array([
          (
            n("request"),
            public_value(
              [("availability", int), ("requested-quantity", int)],
              result,
              body,
            ),
          ),
        ]),
      },
    ),
  ])
}

///|
/// Types, records, cases, lets, lambdas, lists, Maybe and a constrained variable, across two modules.
pub fn shapes() -> @ir.IRFile {
  let float = ty("morphir/SDK:basics#float")
  let shape = ty("acme/shapes:geometry#shape")
  let constructors : @ir.Constructors = Map::from_array([
    (n("circle"), [(n("radius"), float)]),
    (n("rectangle"), [(n("width"), float), (n("height"), float)]),
  ])
  let area = @ir.Value::PatternMatch(v(), local("shape"), [
    (
      ConstructorPattern(v(), fq("acme/shapes:geometry#circle"), [
        AsPattern(v(), WildcardPattern(v()), n("r")),
      ]),
      call("morphir/SDK:basics#multiply", [
        Reference(v(), fq("morphir/SDK:basics#pi")),
        call("morphir/SDK:basics#multiply", [local("r"), local("r")]),
      ]),
    ),
    (
      ConstructorPattern(v(), fq("acme/shapes:geometry#rectangle"), [
        AsPattern(v(), WildcardPattern(v()), n("w")),
        AsPattern(v(), WildcardPattern(v()), n("h")),
      ]),
      call("morphir/SDK:basics#multiply", [local("w"), local("h")]),
    ),
  ])
  let number = @ir.Type::Variable(
    {
      ..t(),
      constraints: Map::from_array([("typeclass", @ir.Data::Text("number"))]),
    },
    n("a"),
  )
  let largest_body = call("morphir/SDK:list#maximum", [local("values")])
  let total = @ir.Value::LetDefinition(
    v(),
    n("areas"),
    ExpressionBody(
      [],
      ty("morphir/SDK:list#list", args=[float]),
      call("morphir/SDK:list#map", [
        Reference(v(), fq("acme/shapes:geometry#area")),
        local("shapes"),
      ]),
    ),
    call("morphir/SDK:list#sum", [local("areas")]),
  )
  let scaled = @ir.Value::Lambda(
    v(),
    AsPattern(v(), WildcardPattern(v()), n("s")),
    @ir.Value::UpdateRecord(
      v(),
      local("s"),
      Map::from_array([(n("scale"), Literal(v(), FloatLiteral(2.0)))]),
    ),
  )
  library("acme/shapes", [
    (
      "geometry",
      {
        types: Map::from_array([
          (
            n("shape"),
            {
              access: Public,
              value: {
                doc: Some("A shape."),
                value: CustomTypeDefinition([], {
                  access: Public,
                  value: constructors,
                }),
              },
            },
          ),
        ]),
        doc: Some("Geometry."),
        values: Map::from_array([
          (n("area"), public_value([("shape", shape)], float, area)),
          (
            n("largest"),
            public_value(
              [("values", ty("morphir/SDK:list#list", args=[number]))],
              ty("morphir/SDK:maybe#maybe", args=[number]),
              largest_body,
            ),
          ),
        ]),
      },
    ),
    (
      "report",
      {
        types: Map::from_array([
          (
            n("view"),
            {
              access: Public,
              value: {
                doc: None,
                value: TypeAliasDefinition(
                  [],
                  Record(t(), Map::from_array([(n("scale"), float)])),
                ),
              },
            },
          ),
        ]),
        doc: None,
        values: Map::from_array([
          (
            n("total-area"),
            public_value(
              [("shapes", ty("morphir/SDK:list#list", args=[shape]))],
              float,
              total,
            ),
          ),
          (
            n("double-scale"),
            public_value(
              [],
              Function(
                t(),
                ty("acme/shapes:report#view"),
                ty("acme/shapes:report#view"),
              ),
              scaled,
            ),
          ),
        ]),
      },
    ),
  ])
}

///|
/// Two modules that each hold a decimal literal, which the backend refuses.
pub fn refused() -> @ir.IRFile {
  let decimal = ty("morphir/SDK:decimal#decimal")
  let make = fn(doc : String) -> @ir.ModuleDefinition {
    {
      types: Map([]),
      doc: Some(doc),
      values: Map::from_array([
        (
          n("rate"),
          public_value([], decimal, Literal(v(), DecimalLiteral("1.5"))),
        ),
      ]),
    }
  }
  library("acme/rates", [("first", make("First.")), ("second", make("Second."))])
}

///|
/// A specification distribution: types only and value specifications.
pub fn specs() -> @ir.IRFile {
  let int = ty("morphir/SDK:basics#int")
  @ir.IRFile::new(
    Specs(@ir.Path::parse("acme/api") catch { _ => panic() }, Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("limits") catch {
            _ => panic()
          },
          {
            annotations: [],
            types: Map::from_array([
              (
                n("limit"),
                {
                  doc: None,
                  value: {
                    annotations: [],
                    body: TypeAliasSpecification([], int),
                  },
                },
              ),
              (
                n("token"),
                {
                  doc: None,
                  value: { annotations: [], body: OpaqueTypeSpecification([]), },
                },
              ),
            ]),
            values: Map::from_array([
              (
                n("max-limit"),
                {
                  doc: None,
                  value: {
                    annotations: [Compact(fq("acme/api:tags#stable"), None)],
                    inputs: [],
                    output: int,
                  },
                },
              ),
            ]),
            doc: None,
          },
        ),
      ]),
    }),
  ) catch {
    _ => panic()
  }
}
