///|
fn deps() -> Map[@ir.PackageName, @ir.PackageSpecification] {
  Map::from_array([
    (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
  ])
}

///|
fn classic() -> Array[(String, @ir.IRFile)] {
  [
    ("classic-greeting", @elm_fixtures.classic_greeting()),
    ("classic-rentals-v1", @elm_fixtures.classic_rentals_v1()),
    ("classic-rentals-v2", @elm_fixtures.classic_rentals_v2()),
  ]
}

///|
/// `strip_node_types` keeps the top-level signatures. Classic IR does not separate annotated top-level signatures
/// from inferred ones, so stripping them would give types that are correctly more general than the Elm annotations,
/// for example `comparable` for an `Int` parameter. `strip_node_types` clears every node type and marks morphir-elm's let
/// placeholders (`mark_classic_let_placeholders`). Inference must then give every node type and every
/// signature type that is not a placeholder, up to variable renaming and alias expansion.
test "criterion B: stripped classic IR infers the morphir-elm types" {
  for entry in classic() {
    let (name, original) = entry
    let filled = @typing.infer(strip_node_types(original), deps(), Fill) catch {
      InferenceFailed(problems) =>
        fail(
          name +
          ": " +
          problems
          .map(p => p.code + " at " + p.node + ": " + p.message)
          .join("; "),
        )
    }
    let mismatches = compare_types(original, filled)
    assert_eq(mismatches, [], msg=name)
  }
}

///|
/// Classic IR is checked strictly, after morphir-elm's let placeholders are marked: they are not annotations.
test "criterion C: classic IR passes check unchanged, and a mutation is found" {
  for entry in classic() {
    let (name, original) = entry
    let original = mark_classic_let_placeholders(original)
    assert_eq(@typing.infer(original, deps(), Check), original, msg=name)
    let (mutated, path) = mutate_first_literal_type(original)
    let codes = try {
      ignore(@typing.infer(mutated, deps(), Check))
      []
    } catch {
      InferenceFailed(problems) => problems.map(p => (p.code, p.node))
    }
    assert_eq(codes, [("annotation_mismatch", path)], msg=name)
  }
}

///|
/// `strip_full` also replaces every top-level signature type with an unknown variable, so inference must solve
/// every signature and type every node.
test "criterion A: every fixture corpus fills completely" {
  let corpus : Array[(String, @ir.IRFile)] = [
    ("elm-rentals", @elm_fixtures.rentals()),
    ("elm-shapes", @elm_fixtures.shapes()),
  ]
  let moonbit = [
    ("moonbit-library", @fixtures.library()),
    ("moonbit-pricing", @fixtures.pricing()),
    ("moonbit-acceptance", @fixtures.acceptance_library()),
    ("moonbit-invocation", @fixtures.invocation_library()),
    ("moonbit-conformance", @fixtures.conformance()),
    ("moonbit-rust", @fixtures.rust_conformance()),
  ] catch {
    _ => fail("fixture")
  }
  for item in moonbit {
    corpus.push(item)
  }
  for entry in corpus {
    let (name, file) = entry
    let filled = @typing.infer(strip_full(file), deps(), Fill) catch {
      InferenceFailed(problems) =>
        fail(
          name + ": " + problems.map(p => p.code + " at " + p.node).join("; "),
        )
    }
    assert_eq(count_untyped(filled), 0, msg=name)
    assert_eq(marked_signatures(filled), [], msg=name)
  }
}

///|
/// The signature paths of `file` whose types still have a variable with the unknown marker.
fn marked_signatures(file : @ir.IRFile) -> Array[String] {
  let out : Array[String] = []
  visit(file, (_, _, _) => (), (def, path, _) => {
    for entry in signature_entries(def, path) {
      if has_marked_variable(entry.1) {
        out.push(entry.0)
      }
    }
  })
  out
}

///|
fn has_marked_variable(t : @ir.Type) -> Bool {
  let marked = fn(attrs : @ir.TypeAttributes) {
    attrs.extensions.get("morphir.inference") is Some(Text("unknown"))
  }
  match t {
    Variable(attrs, _) => marked(attrs)
    Unit(_) => false
    Reference(_, _, items) | Tuple(_, items) =>
      items.iter().any(has_marked_variable)
    Record(_, fields) => fields.values().any(has_marked_variable)
    ExtensibleRecord(attrs, _, fields) =>
      marked(attrs) || fields.values().any(has_marked_variable)
    Function(_, input, output) =>
      has_marked_variable(input) || has_marked_variable(output)
  }
}

///|
test "placeholders: only t-<digits> variables of let signatures are marked" {
  assert_true(is_placeholder(@ir.Name::from_words(["t", "8"])))
  assert_true(is_placeholder(@ir.Name::from_words(["t", "12"])))
  assert_false(is_placeholder(@ir.Name::from_words(["t"])))
  assert_false(is_placeholder(@ir.Name::from_words(["t", "a"])))
  assert_false(is_placeholder(@ir.Name::from_words(["comparable"])))
  // classic-greeting has exactly one placeholder signature type: the output of the `discount` let.
  let greeting = @elm_fixtures.classic_greeting()
  let all = typed_entries(greeting, false)
  let kept = typed_entries(greeting, true)
  assert_eq(all.filter(e => !kept.iter().any(k => k.0 == e.0)).map(e => e.0), [
    "value:elm-compat:main#apply-discount/body/definition:output",
  ])
  // Marking changes only that let signature.
  let marked = mark_classic_let_placeholders(greeting)
  assert_true(marked != greeting)
  // A top-level signature path has no `/body` step.
  let top_level = typed_entries(marked, false).filter(e => {
    !e.0.contains("/body")
  })
  assert_true(top_level.length() > 0)
  assert_eq(top_level, all.filter(e => !e.0.contains("/body")))
}

///|
test "the oracle reports a changed node type" {
  let original = @elm_fixtures.classic_rentals_v1()
  let (mutated, path) = mutate_first_literal_type(original)
  let lines = compare_types(original, mutated)
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix(path + ": expected "))
  assert_eq(compare_types(original, original), [])
  assert_true(count_untyped(strip_node_types(original)) > 0)
  assert_true(count_untyped(strip_full(original)) > 0)
  // `strip_full` marks every top-level signature type, and `strip_node_types` marks none.
  let top_level = fn(file : @ir.IRFile) {
    typed_entries(file, false).filter(e => !e.0.contains("/body")).map(e => e.0)
  }
  assert_true(top_level(original).length() > 0)
  assert_eq(marked_signatures(strip_full(original)), top_level(original))
  assert_eq(marked_signatures(strip_node_types(original)), [])
  assert_eq(count_untyped(original), 0)
}
