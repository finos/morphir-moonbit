///|
fn rewrite_fixture() -> @data.IRUnit raise {
  @data.IRUnit::new("pricing", @fixtures.library(), metadata=[
    {
      node_id: "value:pricing:scalars#rate/body",
      data: @ion_text.read_ion(
        "unknown::unknown::{amount:12.340d0,blob:{{/wCA}},nil:null.int,duplicate:1,duplicate:2}",
      ),
    },
  ])
}

///|
fn remove_rate(unit : @data.IRUnit) -> @ir.IRFile raise {
  guard unit.distribution.distribution is Library(name, deps, def) else {
    fail("library")
  }
  let modules = def.modules.copy()
  let key = @ir.Path::parse("scalars")
  let entry = modules[key]
  let values = entry.value.values.copy()
  values.remove(@ir.Name::parse("rate"))
  modules[key] = { ..entry, value: { ..entry.value, values, }, }
  @ir.IRFile::new(@ir.Distribution::Library(name, deps, { modules, }))
}

///|
test "identity preserves rich Ion metadata and ordered annotations without projection" {
  let unit = rewrite_fixture()
  let result = @data.apply_rewrite(
    unit,
    { distribution: unit.distribution, lineage: None, },
    "identity",
    "retain",
    @data.MetadataPolicy::retain(),
  )
  assert_true(result.metadata[0].data.equals(unit.metadata[0].data))
  assert_eq(result.annotations, unit.annotations)
  assert_true(result.provenance.is_empty())
  // A semantic JSON component sees only IR, while a whole-unit export remains loss-aware.
  let projected = @data.semantic_json(unit)
  assert_eq(@ir_json.read(projected), unit.distribution)
  assert_true(
    try {
      ignore(@data.Registry::new().encode("morphir-json", unit))
      false
    } catch {
      @data.Invalid(code, _) => code == "data.lossy_conversion"
      _ => false
    },
  )
}

///|
test "structural rewrites require complete lineage and record removed rich metadata" {
  let unit = rewrite_fixture()
  let distribution = remove_rate(unit)
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          { distribution, lineage: None, },
          "remove",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.lineage_required"
      _ => false
    },
  )
  let before = @identities.nodes(unit.id, unit.distribution)
  let after = @identities.nodes(unit.id, distribution)
  let lineage : @data.Lineage = {
    retained: before.filter(id => after.contains(id)).map(id => (id, id)),
    removed: before.filter(id => !after.contains(id)),
    derived: [],
  }
  let result = @data.apply_rewrite(
    unit,
    { distribution, lineage: Some(lineage), },
    "remove-rate",
    "retain",
    @data.MetadataPolicy::retain(),
  )
  assert_true(result.metadata.is_empty())
  assert_eq(result.provenance.length(), 1)
  assert_true(lineage.removed.contains(unit.metadata[0].node_id))
  guard result.provenance[0].kind() is Struct(fields) else {
    fail("provenance")
  }
  let removed = fields
    .iter()
    .find_first(f => f.name().text() == Some("removed_metadata"))
    .unwrap()
    .value()
  guard removed.kind() is List([entry]) else { fail("removed metadata") }
  guard entry.kind() is Struct(entries) else { fail("entry") }
  assert_true(entries[1].value().equals(unit.metadata[0].data))
  for codec in ["ion-text", "ion-binary"] {
    let registry = @data.Registry::new()
    let restored = registry.decode(codec, {
      unit_id: unit.id,
      content: registry.encode(codec, result),
    })
    assert_true(restored.provenance[0].equals(result.provenance[0]))
  }
  let incomplete : @data.Lineage = { retained: [], derived: [], removed: [], }
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          { distribution, lineage: Some(incomplete), },
          "remove",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.incomplete_lineage"
      _ => false
    },
  )
}

///|
test "derived node metadata requires a registered policy and preserves unknown data" {
  let unit = rewrite_fixture()
  let source = unit.metadata[0].node_id
  let identity = @data.Lineage::identity(unit)
  let lineage : @data.Lineage = {
    retained: identity.retained.filter(p => p.0 != source),
    removed: [source],
    derived: [(source, [source])],
  }
  let rewrite : @data.Rewrite = {
    distribution: unit.distribution,
    lineage: Some(lineage),
  }
  assert_true(
    try {
      ignore(
        @data.apply_rewrite(
          unit,
          rewrite,
          "derive",
          "retain",
          @data.MetadataPolicy::retain(),
        ),
      )
      false
    } catch {
      @data.Invalid(code, _) => code == "data.metadata_policy_required"
      _ => false
    },
  )
  let result = @data.apply_rewrite(
    unit,
    rewrite,
    "derive",
    "copy-single-origin",
    @data.MetadataPolicy::copy_single_origin(),
  )
  assert_eq(result.metadata[0].node_id, source)
  assert_true(result.metadata[0].data.equals(unit.metadata[0].data))
  assert_eq(result.metadata[0].data.annotations().map(t => t.text()), [
    Some("unknown"),
    Some("unknown"),
  ])
  assert_eq(result.provenance.length(), 1)
}
