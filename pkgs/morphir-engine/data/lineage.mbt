///|
pub(all) struct Lineage {
  retained : Array[(String, String)]
  derived : Array[(String, Array[String])]
  removed : Array[String]
}

///|
pub fn Lineage::identity(unit : IRUnit) -> Lineage raise {
  {
    retained: @identities.nodes(unit.id, unit.distribution).map(id => (id, id)),
    derived: [],
    removed: [],
  }
}

///|
pub(all) struct Rewrite {
  distribution : @ir.IRFile
  lineage : Lineage?
}

///|
pub(all) struct MetadataPolicy {
  propagate : (String, Array[NodeMetadata]) -> @ion.IonValue? raise
}

///|
pub fn MetadataPolicy::retain() -> MetadataPolicy {
  {
    propagate: fn(id, origins) raise {
      if !origins.is_empty() {
        raise Invalid(
          "data.metadata_policy_required",
          "Derived metadata for " + id,
        )
      }
      None
    },
  }
}

///|
pub fn MetadataPolicy::copy_single_origin() -> MetadataPolicy {
  {
    propagate: fn(id, origins) raise {
      if origins.length() > 1 {
        raise Invalid("data.metadata_merge_required", id)
      }
      origins.get(0).map(m => m.data)
    },
  }
}

///|
fn lineage_record(fields : Array[(String, @ion.IonValue)]) -> @ion.IonValue {
  @ion.IonValue::from_fields(fields.map(p => @ion.Field::new(p.0, p.1)))
}

///|
fn ids_ion(ids : Array[String]) -> @ion.IonValue {
  @ion.IonValue::list(ids.map(@ion.IonValue::string))
}

///|
/// Semantic JSON projection is explicit; rich metadata and annotations never enter it.
pub fn semantic_json(unit : IRUnit) -> String raise {
  @ir_json.write(unit.distribution)
}

///|
pub fn apply_rewrite(
  unit : IRUnit,
  rewrite : Rewrite,
  component : String,
  policy_name : String,
  policy : MetadataPolicy,
) -> IRUnit raise {
  let before = @identities.nodes(unit.id, unit.distribution)
  let after = @identities.nodes(unit.id, rewrite.distribution)
  let lineage = match rewrite.lineage {
    Some(lineage) => lineage
    None if rewrite.distribution == unit.distribution => return unit
    None => raise Invalid("data.lineage_required", component)
  }
  let before_set = Map::from_array(before.map(id => (id, true)))
  let after_set = Map::from_array(after.map(id => (id, true)))
  let sources = Map([])
  let targets = Map([])
  for (source, target) in lineage.retained {
    if !before_set.contains(source) ||
      !after_set.contains(target) ||
      sources.contains(source) ||
      targets.contains(target) {
      raise Invalid("data.invalid_lineage", source + " -> " + target)
    }
    sources[source] = true
    targets[target] = true
  }
  for source in lineage.removed {
    if !before_set.contains(source) || sources.contains(source) {
      raise Invalid("data.invalid_lineage", source)
    }
    sources[source] = true
  }
  for (target, origins) in lineage.derived {
    if !after_set.contains(target) ||
      targets.contains(target) ||
      origins.is_empty() ||
      !origins.all(id => before_set.contains(id)) {
      raise Invalid("data.invalid_lineage", target)
    }
    let seen = Map([])
    for origin in origins {
      if seen.contains(origin) {
        raise Invalid("data.invalid_lineage", "Duplicate origin " + origin)
      }
      seen[origin] = true
    }
    targets[target] = true
  }
  if sources.length() != before.length() || targets.length() != after.length() {
    raise Invalid("data.incomplete_lineage", component)
  }
  let seen = Map([])
  for entry in unit.metadata {
    if !before_set.contains(entry.node_id) || seen.contains(entry.node_id) {
      raise Invalid("data.metadata_identity", entry.node_id)
    }
    seen[entry.node_id] = true
  }
  let metadata = []
  for entry in unit.metadata {
    let target = lineage.retained.iter().find_first(p => p.0 == entry.node_id)
    if target is Some((_, target)) {
      metadata.push({ node_id: target, data: entry.data, })
    }
  }
  for (target, origins) in lineage.derived {
    let propagateed = unit.metadata.filter(m => origins.contains(m.node_id))
    if (policy.propagate)(target, propagateed) is Some(data) {
      metadata.push({ node_id: target, data, })
    }
  }
  let provenance = lineage_record([
    ("component", @ion.IonValue::string(component)),
    ("metadata_policy", @ion.IonValue::string(policy_name)),
    (
      "retained",
      @ion.IonValue::list(
        lineage.retained.map(p => {
          lineage_record([
            ("source", @ion.IonValue::string(p.0)),
            ("target", @ion.IonValue::string(p.1)),
          ])
        }),
      ),
    ),
    (
      "derived",
      @ion.IonValue::list(
        lineage.derived.map(p => {
          lineage_record([
            ("target", @ion.IonValue::string(p.0)),
            ("origins", ids_ion(p.1)),
          ])
        }),
      ),
    ),
    ("removed", ids_ion(lineage.removed)),
    (
      "removed_metadata",
      @ion.IonValue::list(
        unit.metadata
        .filter(m => lineage.removed.contains(m.node_id))
        .map(m => {
          lineage_record([
            ("node_id", @ion.IonValue::string(m.node_id)),
            ("data", m.data),
          ])
        }),
      ),
    ),
  ]).with_annotation(@ion.SymbolToken::new("morphir_rewrite"))
  {
    ..unit,
    distribution: rewrite.distribution,
    metadata,
    provenance: unit.provenance + [provenance],
  }
}
