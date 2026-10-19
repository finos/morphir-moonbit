///|
fn fixture_env() -> @admission.TypeEnvironment {
  @admission.TypeEnvironment::new(profile=@admission.supported_profile, declarations=[
    (
      "PositiveAmount",
      @admission.Transparent([], @admission.TInt, Some(@admission.PositiveInt)),
    ),
    (
      "BorrowerName",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NonEmptyString),
      ),
    ),
    (
      "UserId",
      @admission.Opaque([], @admission.TString, Some(@admission.NonEmptyString)),
    ),
    (
      "Loan",
      @admission.Custom([], [
        (
          "Loan",
          [
            @admission.TRecord([
              ("borrower", @admission.TReference("BorrowerName", [])),
              ("amount", @admission.TReference("PositiveAmount", [])),
              ("tags", @admission.TList(@admission.TString)),
            ]),
          ],
        ),
      ]),
    ),
    (
      "Tree",
      @admission.Custom([], [
        ("Leaf", [@admission.TInt]),
        (
          "Node",
          [@admission.TReference("Tree", []), @admission.TReference("Tree", [])],
        ),
      ]),
    ),
    (
      "Maybe",
      @admission.Custom(["a"], [
        ("None", []),
        ("Some", [@admission.TVariable("a")]),
      ]),
    ),
    (
      "Box",
      @admission.Transparent(
        ["a"],
        @admission.TRecord([("item", @admission.TVariable("a"))]),
        None,
      ),
    ),
    (
      "IntOrText",
      @admission.Transparent(
        [],
        @admission.TUnion([@admission.TInt, @admission.TString]),
        None,
      ),
    ),
    (
      "CycleA",
      @admission.Transparent([], @admission.TReference("CycleB", []), None),
    ),
    (
      "CycleB",
      @admission.Transparent([], @admission.TReference("CycleA", []), None),
    ),
    (
      "NamedOk",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NamedRefinement("string.nonEmpty")),
      ),
    ),
    (
      "Weird",
      @admission.Transparent(
        [],
        @admission.TString,
        Some(@admission.NamedRefinement("text.uppercase")),
      ),
    ),
  ])
}

///|
fn expect_valid(outcome : @admission.Outcome) -> Unit raise {
  assert_true(outcome is Valid)
}

///|
fn expect_invalid(outcome : @admission.Outcome, code : String) -> Unit raise {
  match outcome {
    Invalid(diagnostics) =>
      assert_true(diagnostics.iter().any(d => d.code == code))
    _ => fail("expected Invalid(" + code + "), got a different outcome")
  }
}

///|
fn expect_unsupported(
  outcome : @admission.Outcome,
  code : String,
) -> Unit raise {
  match outcome {
    Unsupported(diagnostic) => assert_eq(diagnostic.code, code)
    _ => fail("expected Unsupported(" + code + "), got a different outcome")
  }
}

///|
test "tracer: a well-formed record value is admitted" {
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TRecord([
      ("borrower", @admission.TString),
      ("amount", @admission.TInt),
    ]),
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("1200")),
    ]),
  )
  expect_valid(outcome)
}

///|
test "records reject missing, extra and mistyped fields" {
  let ty = @admission.TRecord([
    ("borrower", @admission.TString),
    ("amount", @admission.TInt),
  ])
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VRecord([("borrower", @admission.VString("Ada"))]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VRecord([
        ("borrower", @admission.VString("Ada")),
        ("amount", @admission.int_value("1")),
        ("extra", @admission.VBool(true)),
      ]),
    ),
    "contracts.invalid_value",
  )
  let outcome = @admission.admit(
    fixture_env(),
    ty,
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.VString("lots")),
    ]),
  )
  match outcome {
    Invalid(diagnostics) => {
      assert_eq(diagnostics[0].code, "contracts.invalid_value")
      assert_eq(diagnostics[0].path, "/amount")
    }
    _ => fail("expected Invalid for a mistyped field")
  }
}

///|
test "custom types check constructors recursively" {
  let leaf = @admission.VConstructed("Leaf", [@admission.int_value("1")])
  let tree = @admission.VConstructed("Node", [
    leaf,
    @admission.VConstructed("Node", [
      leaf,
      @admission.VConstructed("Leaf", [@admission.int_value("2")]),
    ]),
  ])
  expect_valid(
    @admission.admit(fixture_env(), @admission.TReference("Tree", []), tree),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Node", [
        leaf,
        @admission.VConstructed("Leaf", [@admission.VString("x")]),
      ]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Branch", [leaf]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Tree", []),
      @admission.VConstructed("Leaf", []),
    ),
    "contracts.invalid_value",
  )
}

///|
test "generic declarations instantiate at concrete argument types" {
  let maybe_int = @admission.TReference("Maybe", [@admission.TInt])
  expect_valid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("Some", [@admission.int_value("5")]),
    ),
  )
  expect_valid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("None", []),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      maybe_int,
      @admission.VConstructed("Some", [@admission.VString("five")]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Maybe", []),
      @admission.VConstructed("None", []),
    ),
    "contracts.invalid_value",
  )
  let box_text = @admission.TReference("Box", [@admission.TString])
  expect_valid(
    @admission.admit(
      fixture_env(),
      box_text,
      @admission.VRecord([("item", @admission.VString("sealed"))]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      box_text,
      @admission.VRecord([("item", @admission.int_value("3"))]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "tuples of arbitrary arity check element by element" {
  let ty = @admission.TTuple([
    @admission.TBool,
    @admission.TInt,
    @admission.TString,
    @admission.TInt,
    @admission.TBool,
  ])
  expect_valid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VTuple([
        @admission.VBool(true),
        @admission.int_value("1"),
        @admission.VString("x"),
        @admission.int_value("2"),
        @admission.VBool(false),
      ]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      ty,
      @admission.VTuple([@admission.VBool(true)]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "collections check elements and reject duplicate set or dict keys" {
  expect_valid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TInt),
      @admission.VList([@admission.int_value("1"), @admission.int_value("2")]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TList(@admission.TInt),
      @admission.VList([@admission.VString("one")]),
    ),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TSet(@admission.TInt),
      @admission.VSet([@admission.int_value("1"), @admission.int_value("1")]),
    ),
    "contracts.invalid_value",
  )
  let dict_ty = @admission.TDict(@admission.TString, @admission.TInt)
  expect_valid(
    @admission.admit(
      fixture_env(),
      dict_ty,
      @admission.VDict([(@admission.VString("a"), @admission.int_value("1"))]),
    ),
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      dict_ty,
      @admission.VDict([
        (@admission.VString("a"), @admission.int_value("1")),
        (@admission.VString("a"), @admission.int_value("2")),
      ]),
    ),
    "contracts.invalid_value",
  )
}

///|
test "refinements are respected and exact integers stay exact" {
  let amount = @admission.TReference("PositiveAmount", [])
  expect_valid(
    @admission.admit(
      fixture_env(),
      amount,
      @admission.int_value("9223372036854775807000"),
    ),
  )
  expect_invalid(
    @admission.admit(fixture_env(), amount, @admission.int_value("0")),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(fixture_env(), amount, @admission.int_value("-3")),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("BorrowerName", []),
      @admission.VString(""),
    ),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("NamedOk", []),
      @admission.VString(""),
    ),
    "contracts.refinement_failed",
  )
}

///|
test "opaque types accept only constructed values for the same name" {
  let user_id = @admission.TReference("UserId", [])
  expect_valid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("UserId", @admission.VString("user-1")),
    ),
  )
  expect_invalid(
    @admission.admit(fixture_env(), user_id, @admission.VString("user-1")),
    "contracts.opaque_construction",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("OtherId", @admission.VString("user-1")),
    ),
    "contracts.opaque_construction",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      user_id,
      @admission.VOpaque("UserId", @admission.VString("")),
    ),
    "contracts.refinement_failed",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TString,
      @admission.VOpaque("UserId", @admission.VString("user-1")),
    ),
    "contracts.opaque_construction",
  )
}

///|
test "unions admit exactly one matching member and report ambiguity" {
  let union_ty = @admission.TReference("IntOrText", [])
  expect_valid(
    @admission.admit(fixture_env(), union_ty, @admission.int_value("7")),
  )
  expect_valid(
    @admission.admit(fixture_env(), union_ty, @admission.VString("seven")),
  )
  expect_invalid(
    @admission.admit(fixture_env(), union_ty, @admission.VBool(true)),
    "contracts.invalid_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([
        @admission.TReference("PositiveAmount", []),
        @admission.TInt,
      ]),
      @admission.int_value("5"),
    ),
    "contracts.ambiguous_value",
  )
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([]),
      @admission.int_value("5"),
    ),
    "contracts.invalid_value",
  )
}

///|
test "unsupported types and missing information are reported" {
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TFunction([@admission.TInt], @admission.TInt),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TUnsupported("Decimal"),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Missing", []),
      @admission.int_value("1"),
    ),
    "contracts.unknown_type",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TVariable("a"),
      @admission.int_value("1"),
    ),
    "contracts.unbound_variable",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TReference("Weird", []),
      @admission.VString("HELLO"),
    ),
    "contracts.unsupported_refinement",
  )
  expect_unsupported(
    @admission.admit(
      fixture_env(),
      @admission.TUnion([
        @admission.TInt,
        @admission.TFunction([], @admission.TInt),
      ]),
      @admission.int_value("1"),
    ),
    "contracts.unsupported_type",
  )
}

///|
test "budgets never pass an exhausted check" {
  let no_nodes : @admission.Limits = { max_depth: 128, max_nodes: 0, }
  let outcome = @admission.admit(
    fixture_env(),
    @admission.TBool,
    @admission.VBool(true),
    limits=no_nodes,
  )
  assert_true(outcome is Exhausted(NodeLimit))
  let shallow : @admission.Limits = { max_depth: 2, max_nodes: 100, }
  let deep = @admission.admit(
    fixture_env(),
    @admission.TList(@admission.TList(@admission.TInt)),
    @admission.VList([@admission.VList([@admission.int_value("1")])]),
    limits=shallow,
  )
  assert_true(deep is Exhausted(DepthLimit))
  let tree_ty = @admission.TReference("Tree", [])
  let mut value = @admission.VConstructed("Leaf", [@admission.int_value("0")])
  for _ in 0..<40 {
    value = @admission.VConstructed("Node", [value, value])
  }
  let bounded : @admission.Limits = { max_depth: 16, max_nodes: 100000, }
  assert_true(
    @admission.admit(fixture_env(), tree_ty, value, limits=bounded)
    is Exhausted(_),
  )
}

///|
test "alias cycles fail instead of looping" {
  expect_invalid(
    @admission.admit(
      fixture_env(),
      @admission.TReference("CycleA", []),
      @admission.VString("x"),
    ),
    "contracts.alias_cycle",
  )
}

///|
test "profile and declaration errors are reported before checking" {
  let wrong_profile = @admission.TypeEnvironment::new(
    profile="morphir-contracts/9.9.9",
    declarations=[],
  )
  expect_unsupported(
    @admission.admit(wrong_profile, @admission.TBool, @admission.VBool(true)),
    "contracts.unsupported_profile",
  )
  let duplicated = @admission.TypeEnvironment::new(
    profile=@admission.supported_profile,
    declarations=[
      ("Dup", @admission.Transparent([], @admission.TInt, None)),
      ("Dup", @admission.Transparent([], @admission.TString, None)),
    ],
  )
  expect_invalid(
    @admission.admit(
      duplicated,
      @admission.TReference("Dup", []),
      @admission.int_value("1"),
    ),
    "contracts.duplicate_declaration",
  )
}

///|
test "nested declarations compose inside custom payloads" {
  let loan = @admission.VConstructed("Loan", [
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("1200")),
      ("tags", @admission.VList([@admission.VString("first")])),
    ]),
  ])
  expect_valid(
    @admission.admit(fixture_env(), @admission.TReference("Loan", []), loan),
  )
  let bad_loan = @admission.VConstructed("Loan", [
    @admission.VRecord([
      ("borrower", @admission.VString("Ada")),
      ("amount", @admission.int_value("-1")),
      ("tags", @admission.VList([])),
    ]),
  ])
  expect_invalid(
    @admission.admit(fixture_env(), @admission.TReference("Loan", []), bad_loan),
    "contracts.refinement_failed",
  )
}
