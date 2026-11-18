///|
/// Selected documents from the contextual orders fixtures.
/// Exact source bytes from finos/morphir at 177371fa7a6199b7f177a8c1d886f583ee57e813.
/// Source: spec/mck/bounded-generation/fixtures/acme-orders.
fn contextual_orders_v3_json() -> Array[(String, String)] {
  let manifest =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "packagePaths": { "p": "acme/orders", "d": "morphir/SDK" } },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "distribution": "Library",
    #|    "package": { "$name": "p" },
    #|    "pathBudget": 4000,
    #|    "dependencies": [{ "$name": "d" }]
    #|  }
    #|}
    #|
  let domain =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "domain" },
    #|    "names": { "o": "order", "t": "total-in-USD" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "path": { "$name": "m" },
    #|    "doc": "Order totals.",
    #|    "types": [{ "$name": "o" }],
    #|    "values": [{ "$name": "o" }, { "$name": "t" }]
    #|  }
    #|}
    #|
  let total =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "total-in-USD" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int", "o": "acme/orders:domain#order" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "access": "Public",
    #|      "value": { "doc": "", "value": {
    #|        "inputTypes": [],
    #|        "outputType": ["Reference", {}, { "$name": "i" }, []],
    #|        "body": ["Reference", ["Reference", {}, { "$name": "i" }, []], { "$name": "o" }]
    #|      } }
    #|    }
    #|  }
    #|}
    #|
  let order_type =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "access": "Public",
    #|      "value": { "doc": "", "value": [
    #|        "TypeAliasDefinition",
    #|        [],
    #|        ["Reference", {}, { "$name": "i" }, []]
    #|      ] }
    #|    }
    #|  }
    #|}
    #|
  let sdk_module =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "basics" },
    #|    "names": { "i": "int", "a": "add" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "path": { "$name": "m" },
    #|    "doc": "Integer operations.",
    #|    "types": [{ "$name": "i" }],
    #|    "values": [{ "$name": "a" }]
    #|  }
    #|}
    #|
  let sdk_type =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "names": { "n": "int" } },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] }
    #|  }
    #|}
    #|
  [
    ("pkg/acme/orders/domain/order.type.json", order_type),
    ("deps/morphir/_sdk/@/basics/module.json", sdk_module),
    ("deps/morphir/_sdk/@/basics/int.type.json", sdk_type),
    ("manifest.json", manifest),
    ("pkg/acme/orders/domain/module.json", domain),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", total),
  ]
}

///|
fn contextual_orders_v3_yaml() -> Array[(String, String)] {
  let manifest =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  packagePaths:
    #|    p: acme/orders
    #|    d: morphir/SDK
    #|document:
    #|  formatVersion: 3.1.0
    #|  distribution: Library
    #|  package:
    #|    $name: p
    #|  pathBudget: 4000
    #|  dependencies:
    #|    - $name: d
    #|
  let domain =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: domain
    #|  names:
    #|    o: order
    #|    t: total-in-USD
    #|document:
    #|  formatVersion: 3.1.0
    #|  path:
    #|    $name: m
    #|  doc: Order totals.
    #|  types:
    #|    - $name: o
    #|  values:
    #|    - $name: o
    #|    - $name: t
    #|
  let total =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": total-in-USD
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|    o: "acme/orders:domain#order"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    access: Public
    #|    value:
    #|      doc: ""
    #|      value:
    #|        inputTypes:
    #|          []
    #|        outputType:
    #|          - Reference
    #|          - {}
    #|          - $name: i
    #|          - []
    #|        body:
    #|          - Reference
    #|          - - Reference
    #|            - {}
    #|            - $name: i
    #|            - []
    #|          - $name: o
    #|
  let order_type =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    access: Public
    #|    value:
    #|      doc: ""
    #|      value:
    #|        - TypeAliasDefinition
    #|        - []
    #|        - - Reference
    #|          - {}
    #|          - $name: i
    #|          - []
    #|
  let sdk_module =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: basics
    #|  names:
    #|    i: int
    #|    a: add
    #|document:
    #|  formatVersion: 3.1.0
    #|  path:
    #|    $name: m
    #|  doc: Integer operations.
    #|  types:
    #|    - $name: i
    #|  values:
    #|    - $name: a
    #|
  let sdk_type =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": int
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    doc: ""
    #|    value:
    #|      - OpaqueTypeSpecification
    #|      - []
    #|
  [
    ("pkg/acme/orders/domain/order.type.yaml", order_type),
    ("deps/morphir/_sdk/@/basics/module.yaml", sdk_module),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", sdk_type),
    ("manifest.yaml", manifest),
    ("pkg/acme/orders/domain/module.yaml", domain),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", total),
  ]
}

///|
fn contextual_orders_v4_json() -> Array[(String, String)] {
  let manifest =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "packagePaths": { "p": "acme/orders", "d": "morphir/SDK" } },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "distribution": "Library",
    #|    "package": { "$name": "p" },
    #|    "pathBudget": 4000,
    #|    "dependencies": [{ "$name": "d" }]
    #|  }
    #|}
    #|
  let domain =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "domain" },
    #|    "names": { "o": "order", "t": "total-in-USD" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "path": { "$name": "m" },
    #|    "doc": "Order totals.",
    #|    "types": [{ "$name": "o" }],
    #|    "values": [{ "$name": "o" }, { "$name": "t" }]
    #|  }
    #|}
    #|
  let total =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "total-in-USD" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int", "o": "acme/orders:domain#order" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "Public": {
    #|        "ExpressionBody": {
    #|          "inputTypes": {},
    #|          "outputType": { "$name": "i" },
    #|          "body": { "Reference": { "$name": "o" } }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let order_type =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "Public": {
    #|        "TypeAliasDefinition": { "typeParams": [], "typeExp": { "$name": "i" } }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let sdk_module =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "basics" },
    #|    "names": { "i": "int", "a": "add" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "path": { "$name": "m" },
    #|    "doc": "Integer operations.",
    #|    "types": [{ "$name": "i" }],
    #|    "values": [{ "$name": "a" }]
    #|  }
    #|}
    #|
  let sdk_type =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "names": { "n": "int" } },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "spec": { "OpaqueTypeSpecification": {} }
    #|  }
    #|}
    #|
  [
    ("pkg/acme/orders/domain/order.type.json", order_type),
    ("deps/morphir/_sdk/@/basics/module.json", sdk_module),
    ("deps/morphir/_sdk/@/basics/int.type.json", sdk_type),
    ("manifest.json", manifest),
    ("pkg/acme/orders/domain/module.json", domain),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", total),
  ]
}

///|
fn contextual_orders_v4_yaml() -> Array[(String, String)] {
  let manifest =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  packagePaths:
    #|    p: acme/orders
    #|    d: morphir/SDK
    #|document:
    #|  formatVersion: 4
    #|  distribution: Library
    #|  package:
    #|    $name: p
    #|  pathBudget: 4000
    #|  dependencies:
    #|    - $name: d
    #|
  let domain =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: domain
    #|  names:
    #|    o: order
    #|    t: total-in-USD
    #|document:
    #|  formatVersion: 4
    #|  path:
    #|    $name: m
    #|  doc: Order totals.
    #|  types:
    #|    - $name: o
    #|  values:
    #|    - $name: o
    #|    - $name: t
    #|
  let total =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": total-in-USD
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|    o: "acme/orders:domain#order"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    Public:
    #|      ExpressionBody:
    #|        inputTypes:
    #|          {}
    #|        outputType:
    #|          $name: i
    #|        body:
    #|          Reference:
    #|            $name: o
    #|
  let order_type =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    Public:
    #|      TypeAliasDefinition:
    #|        typeParams:
    #|          []
    #|        typeExp:
    #|          $name: i
    #|
  let sdk_module =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: basics
    #|  names:
    #|    i: int
    #|    a: add
    #|document:
    #|  formatVersion: 4
    #|  path:
    #|    $name: m
    #|  doc: Integer operations.
    #|  types:
    #|    - $name: i
    #|  values:
    #|    - $name: a
    #|
  let sdk_type =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": int
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    OpaqueTypeSpecification:
    #|      {}
    #|
  [
    ("pkg/acme/orders/domain/order.type.yaml", order_type),
    ("deps/morphir/_sdk/@/basics/module.yaml", sdk_module),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", sdk_type),
    ("manifest.yaml", manifest),
    ("pkg/acme/orders/domain/module.yaml", domain),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", total),
  ]
}

///|
test "contextual headers resolve package, module and listed names before opening a body" {
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  for
    (files, extension) in [
      (contextual_orders_v3_json(), ".json"),
      (contextual_orders_v3_yaml(), ".yaml"),
      (contextual_orders_v4_json(), ".json"),
      (contextual_orders_v4_yaml(), ".yaml"),
    ] {
    let tree = recording_tree(files)
    let reader = @yaml.open_bounded_tree(
      tree.source(),
      encoding=@yaml.ContextualDraft1,
    )
    assert_eq(reader.package_name(), package_name)
    let page = reader.members(package_name, module_name, limit=2)
    assert_eq(page.items.map(item => item.name.to_canonical()), [
      "order", "order",
    ])
    assert_true(page.next is Some(_))
    assert_eq(tree.opens, [
      "manifest" + extension,
      "pkg/acme/orders/domain/module" + extension,
    ])
  }
}

///|
fn check_contextual_selected_member(
  files : Array[(String, String)],
  extension : String,
) -> Unit raise {
  let package_name = @ir.Path::parse("acme/orders")
  let module_name = @ir.Path::parse("domain")
  let tree = recording_tree(files)
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let page = reader.members(package_name, module_name, limit=2)
  guard page.next is Some(cursor) else {
    fail("expected the second member page")
  }
  let final_page = reader.members(package_name, module_name, limit=2, cursor~)
  assert_eq(final_page.items.map(item => item.document), [
    "pkg/acme/orders/domain/total-in-_usd.value",
  ])
  let selected = reader.read_member(
    package_name,
    module_name,
    ValueMember,
    final_page.items[0].name,
  )
  let reference = match selected {
    V3ValueDefinition(definition) => {
      let value = definition.value.value
      guard value.output_type is Reference(_, output, []) &&
        value.body is Reference(Reference(_, inferred, []), reference) else {
        fail("expected the v3 reference and classic inferred type")
      }
      assert_eq(output.to_canonical(), "morphir/SDK:basics#int")
      assert_eq(inferred, output)
      reference
    }
    V4ValueDefinition(definition) => {
      guard definition.value.value
        is ExpressionBody([], Reference(_, output, []), Reference(_, reference)) else {
        fail("expected the v4 value and its bare FQName type")
      }
      assert_eq(output.to_canonical(), "morphir/SDK:basics#int")
      reference
    }
    _ => fail("expected a contextual value definition")
  }
  assert_eq(reference.to_canonical(), "acme/orders:domain#order")
  assert_eq(tree.opens.filter(path => path.contains(".value.")), [
    "pkg/acme/orders/domain/total-in-_usd.value" + extension,
  ])
}

///|
test "bounded v3.1 contextual JSON reads only the selected orders value" {
  check_contextual_selected_member(contextual_orders_v3_json(), ".json")
}

///|
test "bounded v3.1 contextual YAML reads only the selected orders value" {
  check_contextual_selected_member(contextual_orders_v3_yaml(), ".yaml")
}

///|
test "bounded v4 contextual JSON reads only the selected orders value" {
  check_contextual_selected_member(contextual_orders_v4_json(), ".json")
}

///|
test "bounded v4 contextual YAML reads only the selected orders value" {
  check_contextual_selected_member(contextual_orders_v4_yaml(), ".yaml")
}

///|
test "plain bounded reader refuses a contextual manifest" {
  let tree = recording_tree(contextual_orders_v4_json())
  assert_true(
    tree_failure(() => @yaml.open_bounded_tree(tree.source())) is Some(_),
  )
  assert_eq(tree.opens, ["manifest.json"])
}

///|
test "a package alias cannot resolve in the names table" {
  let manifest =
    #|{
    #|  "$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context":{"names":{"p":"orders"}},
    #|  "document":{"formatVersion":4,"distribution":"Library","package":{"$name":"p"},"pathBudget":4000}
    #|}
  let tree = recording_tree([("manifest.json", manifest)])
  assert_tree_error(
    () => {
      @yaml.open_bounded_tree(tree.source(), encoding=@yaml.ContextualDraft1)
    },
    "context.unknown_alias",
    "manifest/package",
  )
}

///|
test "contextual JSON classifies duplicates by enclosing object even with a late schema" {
  let schema = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"
  let document = "\"document\":{\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"acme/orders\",\"pathBudget\":4000}"
  for
    (members, code, location) in [
      (
        "\"context\":{},\"context\":{}," + document,
        "context.duplicate_entry",
        "/context",
      ),
      (
        "\"context\":{\"names\":{},\"names\":{}}," + document,
        "context.duplicate_entry",
        "/context/names",
      ),
      (
        "\"context\":{\"names\":{\"a\":\"order\",\"a\":\"other\"}}," + document,
        "context.duplicate_entry",
        "/context/names/a",
      ),
      (
        "\"context\":{}," +
        document.replace_all(
          old="\"formatVersion\":4",
          new="\"formatVersion\":4,\"formatVersion\":4",
        ),
        "duplicate_member",
        "formatVersion",
      ),
    ] {
    let tree = recording_tree([
      ("manifest.json", "{" + members + ",\"$schema\":\"" + schema + "\"}"),
    ])
    assert_contextual_manifest_error(tree, code, location)
  }
}

///|
test "contextual YAML classifies duplicates without changing nested document diagnostics" {
  let schema = "$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json\n"
  let document = "document:\n  formatVersion: 4\n  distribution: Library\n  package: acme/orders\n  pathBudget: 4000\n"
  for
    (members, code, location) in [
      (
        "context: {}\ncontext: {}\n" + document,
        "context.duplicate_entry",
        "/context",
      ),
      (
        "context:\n  names: {}\n  names: {}\n" + document,
        "context.duplicate_entry",
        "/context/names",
      ),
      (
        "context:\n  names:\n    a: order\n    a: other\n" + document,
        "context.duplicate_entry",
        "/context/names/a",
      ),
      (
        "context: {}\n" +
        document.replace_all(
          old="  formatVersion: 4\n",
          new="  formatVersion: 4\n  formatVersion: 4\n",
        ),
        "duplicate_member",
        "formatVersion",
      ),
    ] {
    let tree = recording_tree([("manifest.yaml", members + schema)])
    assert_contextual_manifest_error(tree, code, location)
  }
}

///|
fn assert_contextual_manifest_error(
  tree : RecordingTree,
  code : String,
  location : String,
) -> Unit raise {
  let open_tree = () => {
    @yaml.open_bounded_tree(tree.source(), encoding=@yaml.ContextualDraft1)
  }
  guard tree_failure(open_tree) is Some(@wire.Invalid(actual, detail)) else {
    fail("expected a contextual manifest refusal")
  }
  assert_eq(actual, code)
  assert_true(detail.has_prefix("manifest#: ") && detail.contains(location))
}

///|
test "a context-last document gets a second bounded read of the same revision" {
  let schema = "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json"
  let json =
    #|{
    #|  "document":{"formatVersion":4,"distribution":"Library","package":{"$name":"p"},"pathBudget":4000},
    #|  "context":{"packagePaths":{"p":"acme/orders"}},
    #|  "$schema":
  let yaml =
    #|document:
    #|  formatVersion: 4
    #|  distribution: Library
    #|  package:
    #|    $name: p
    #|  pathBudget: 4000
    #|context:
    #|  packagePaths:
    #|    p: acme/orders
    #|$schema:
  for
    (file, input) in [
      ("manifest.json", json + "\"" + schema + "\"}"),
      ("manifest.yaml", yaml + " " + schema + "\n"),
    ] {
    let tree = recording_tree([(file, input)])
    let reader = @yaml.open_bounded_tree(
      tree.source(),
      encoding=@yaml.ContextualDraft1,
    )
    assert_eq(reader.package_name().to_canonical(), "acme/orders")
    assert_eq(tree.opens, [file, file])
    let ordered = recording_tree([(file, input)])
    assert_tree_error(
      () => {
        @yaml.open_bounded_tree(
          ordered.source(),
          encoding=@yaml.ContextualDraft1Ordered,
        )
      },
      "context.after_document",
      "manifest",
    )
    assert_eq(ordered.opens, [file])
  }
}

///|
test "a typed alias resolves while its document-literal lookalike stays opaque" {
  let original = contextual_orders_v4_json()
  let physical = "pkg/acme/orders/domain/total-in-_usd.value.json"
  let artifact =
    #|{
    #|  "$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context":{
    #|    "names":{"x":"total-in-USD"},
    #|    "fqNames":{"x":"morphir/SDK:basics#int"},
    #|    "prefixes":{"future":["é", 4.0]}
    #|  },
    #|  "document":{
    #|    "formatVersion":4,"name":{"$name":"x"},
    #|    "def":{"Public":{"ExpressionBody":{
    #|      "inputTypes":{},"outputType":{"$name":"x"},
    #|      "body":{"Literal":{"DocumentLiteral":{"z":4.0,"$name":"x"}}}
    #|    }}}
    #|  }
    #|}
  let tree = recording_tree(
    original.map(file => {
      if file.0 == physical {
        (physical, artifact)
      } else {
        file
      }
    }),
  )
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let selected = reader.read_member(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    ValueMember,
    @ir.Name::parse("total-in-USD"),
  )
  guard selected is V4ValueDefinition(definition) &&
    definition.value.value
    is ExpressionBody(
      [],
      Reference(_, output, []),
      Literal(_, DocumentLiteral(Object(data)))
    ) else {
    fail("expected typed output and a literal object")
  }
  assert_eq(output.to_canonical(), "morphir/SDK:basics#int")
  let entries = data.iter().collect()
  assert_eq(entries.map(entry => entry.0), ["z", "$name"])
  assert_true(entries[0].1 is Number("4.0"))
  assert_true(entries[1].1 is Text("x"))
  let selection = @yaml.MemberArtifact(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    ValueMember,
    @ir.Name::parse("total-in-USD"),
  )
  assert_eq(reader.read_original_document(selection), (physical, artifact))
  assert_eq(
    reader.read_original_document(@yaml.ManifestArtifact),
    original.filter(file => file.0 == "manifest.json")[0],
  )
  assert_eq(
    reader.read_original_document(
      @yaml.ModuleArtifact(
        @ir.Path::parse("acme/orders"),
        @ir.Path::parse("domain"),
      ),
    ),
    original.filter(file => file.0 == "pkg/acme/orders/domain/module.json")[0],
  )
  let critical = artifact.replace_all(
    old="\"document\":{",
    new="\"critical\":[\"context.prefixes\"],\"document\":{",
  )
  let bad = recording_tree(
    original.map(file => {
      if file.0 == physical {
        (physical, critical)
      } else {
        file
      }
    }),
  )
  let reselected = @yaml.open_bounded_tree(
    bad.source(),
    encoding=@yaml.ContextualDraft1,
  )
  assert_tree_error(
    () => {
      reselected.read_member(
        @ir.Path::parse("acme/orders"),
        @ir.Path::parse("domain"),
        ValueMember,
        @ir.Name::parse("total-in-USD"),
      )
    },
    "context.unknown_critical",
    "pkg/acme/orders/domain/total-in-_usd.value",
  )
  assert_tree_error(
    () => reselected.read_original_document(selection),
    "context.unknown_critical",
    "pkg/acme/orders/domain/total-in-_usd.value",
  )
  tree.revision.val = "revision-2"
  assert_true(
    tree_failure(() => reader.read_original_document(selection))
    is Some(@yaml.TreeSourceError::RevisionChanged),
  )
}

///|
test "application manifest entry-point targets resolve against the manifest context" {
  let manifest =
    #|{
    #|  "$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context":{"fqNames":{"target":"acme/orders:domain#order"}},
    #|  "document":{
    #|    "formatVersion":4,"distribution":"Application","package":"acme/orders","pathBudget":4000,
    #|    "entryPoints":{"main":{"target":{"$name":"target"},"kind":"main"}}
    #|  }
    #|}
  let tree = recording_tree([("manifest.json", manifest)])
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  assert_eq(reader.package_name().to_canonical(), "acme/orders")
  assert_eq(tree.opens, ["manifest.json"])
}

///|
fn manifest_with_context(context : String) -> String {
  "{\"$schema\":\"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json\"," +
  "\"context\":" +
  context +
  ",\"document\":{" +
  "\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"acme/orders\",\"pathBudget\":4000}}"
}

///|
test "context spelling and table limits take precedence over malformed entries" {
  let boundary = "a".repeat(1024)
  let valid = manifest_with_context("{\"names\":{\"n\":\"" + boundary + "\"}}")
  let accepted = recording_tree([("manifest.json", valid)])
  ignore(
    @yaml.open_bounded_tree(accepted.source(), encoding=@yaml.ContextualDraft1),
  )
  for spelling in [boundary + "_", "é".repeat(512) + "a"] {
    let excessive = manifest_with_context(
      "{\"names\":{\"n\":\"" + spelling + "\"}}",
    )
    assert_contextual_manifest_error(
      recording_tree([("manifest.json", excessive)]),
      "context.name_too_long",
      "context.names.n",
    )
  }
  let entries = ["\"n0\":\"order\""]
  for index = 1; index < 16384; index = index + 1 {
    entries.push("\"n" + index.to_string() + "\":\"order\"")
  }
  let defaults = @yaml.Limits::default()
  let limits = { ..defaults, max_assembly_nodes: 500000, }
  let exact = recording_tree([
    (
      "manifest.json",
      manifest_with_context("{\"names\":{" + entries.join(",") + "}}"),
    ),
  ])
  ignore(
    @yaml.open_bounded_tree(
      exact.source(),
      encoding=@yaml.ContextualDraft1,
      limits~,
    ),
  )
  entries.push("\"0\":false")
  let excessive = recording_tree([
    (
      "manifest.json",
      manifest_with_context("{\"names\":{" + entries.join(",") + "}}"),
    ),
  ])
  assert_tree_error(
    () => {
      @yaml.open_bounded_tree(
        excessive.source(),
        encoding=@yaml.ContextualDraft1,
        limits~,
      )
    },
    "context.too_many_entries",
    "manifest",
  )
}

///|
test "unknown context bytes still count against the encoded file limit" {
  let input = manifest_with_context("{\"optional\":\"é\"}")
  let tree = recording_tree([("manifest.json", input)])
  let defaults = @yaml.Limits::default()
  // This fixture has one non-ASCII code point, which occupies two UTF-8 bytes.
  let too_small = { ..defaults, max_bytes: input.length(), }
  assert_tree_error(
    () => {
      @yaml.open_bounded_tree(
        tree.source(),
        encoding=@yaml.ContextualDraft1,
        limits=too_small,
      )
    },
    "document_size_limit",
    "manifest",
  )
  let exact = { ..too_small, max_bytes: input.length() + 1, }
  ignore(
    @yaml.open_bounded_tree(
      tree.source(),
      encoding=@yaml.ContextualDraft1,
      limits=exact,
    ),
  )
}

///|
test "YAML syntax refusals precede contextual name admission" {
  let text = contextual_orders_v4_yaml().filter(file => {
      file.0 == "manifest.yaml"
    })[0].1
  for
    input in [
      "%YAML 1.2\n---\n" + text,
      text.replace_all(old="context:\n", new="context: &names\n"),
    ] {
    let tree = recording_tree([("manifest.yaml", input)])
    assert_tree_error(
      () => {
        @yaml.open_bounded_tree(tree.source(), encoding=@yaml.ContextualDraft1)
      },
      "unsupported_yaml_feature",
      "manifest",
    )
  }
}

///|
fn check_contextual_type_members(
  files : Array[(String, String)],
  extension : String,
) -> Unit raise {
  let tree = recording_tree(files)
  let reader = @yaml.open_bounded_tree(
    tree.source(),
    encoding=@yaml.ContextualDraft1,
  )
  let order = reader.read_member(
    @ir.Path::parse("acme/orders"),
    @ir.Path::parse("domain"),
    TypeMember,
    @ir.Name::parse("order"),
  )
  let referred_type = match order {
    V3TypeDefinition(
      {
        value: { value: TypeAliasDefinition([], Reference(_, name, [])), .. },
        ..
      }
    ) => name
    V4TypeDefinition(
      {
        value: { value: TypeAliasDefinition([], Reference(_, name, [])), .. },
        ..
      }
    ) => name
    _ => fail("expected the orders type alias and its SDK reference")
  }
  assert_eq(referred_type.to_canonical(), "morphir/SDK:basics#int")
  let sdk = reader.read_member(
    @ir.Path::parse("morphir/SDK"),
    @ir.Path::parse("basics"),
    TypeMember,
    @ir.Name::parse("int"),
  )
  match sdk {
    V3TypeSpecification({ value: OpaqueTypeSpecification([]), .. }) => ()
    V4TypeSpecification(
      { value: { body: OpaqueTypeSpecification([]), .. }, .. }
    ) => ()
    _ => fail("expected the dependency's opaque int specification")
  }
  assert_eq(tree.opens.filter(path => path.contains(".type.")), [
    "pkg/acme/orders/domain/order.type" + extension,
    "deps/morphir/_sdk/@/basics/int.type" + extension,
  ])
  assert_eq(tree.opens.filter(path => path.contains(".value.")), [])
}

///|
test "bounded v3.1 contextual JSON reads definitions and dependency specifications" {
  check_contextual_type_members(contextual_orders_v3_json(), ".json")
}

///|
test "bounded v3.1 contextual YAML reads definitions and dependency specifications" {
  check_contextual_type_members(contextual_orders_v3_yaml(), ".yaml")
}

///|
test "bounded v4 contextual JSON reads definitions and dependency specifications" {
  check_contextual_type_members(contextual_orders_v4_json(), ".json")
}

///|
test "bounded v4 contextual YAML reads definitions and dependency specifications" {
  check_contextual_type_members(contextual_orders_v4_yaml(), ".yaml")
}
