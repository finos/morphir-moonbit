///|
/// Additive MoonBit numeric SDK inventory. The pinned classic specification is
/// copied before extension so its oracle count and declarations remain stable.
pub fn numeric_sdk_specification() -> @ir.PackageSpecification raise {
  let classic = sdk_specification()
  let modules = Map::from_array(classic.modules.iter().collect())
  let int_path = @ir.Path::parse("int")
  let classic_int = modules[int_path]
  let types = Map::from_array(classic_int.types.iter().collect())
  let values = Map::from_array(classic_int.values.iter().collect())
  let attrs = @ir.TypeAttributes::default()
  let exact = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let provenance = @ir.Annotation::Compact(
    @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
    Some("morphir-sdk-moonbit-numeric-v1"),
  )
  for
    (name, source_name) in [
      ("byte", "Byte"),
      ("uint-16", "UInt16"),
      ("uint-32", "UInt32"),
      ("uint-64", "UInt64"),
    ] {
    let bounded = @ir.Type::Reference(
      attrs,
      @ir.FQName::parse("morphir/SDK:int#" + name),
      [],
    )
    types[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some(source_name + " unsigned boundary type"),
      value: @ir.TypeSpecification::{
        annotations: [provenance],
        body: @ir.TypeSpecificationBody::OpaqueTypeSpecification([]),
      },
    }
    values[@ir.Name::parse("from-" + name)] = @ir.Documented::{
      doc: Some("Exact nonnegative widening from " + source_name),
      value: @ir.ValueSpecification::{
        inputs: [(@ir.Name::parse("value"), bounded)],
        output: exact,
        annotations: [provenance],
      },
    }
    values[@ir.Name::parse("to-" + name)] = @ir.Documented::{
      doc: Some("Checked narrowing to " + source_name),
      value: @ir.ValueSpecification::{
        inputs: [(@ir.Name::parse("value"), exact)],
        output: @ir.Type::Reference(
          attrs,
          @ir.FQName::parse("morphir/SDK:maybe#maybe"),
          [bounded],
        ),
        annotations: [provenance],
      },
    }
  }
  modules[int_path] = @ir.ModuleSpecification::{
    types,
    values,
    doc: classic_int.doc,
    annotations: classic_int.annotations,
  }
  { modules, }
}

///|
pub fn source_integer_specification() -> @ir.PackageSpecification raise {
  let attrs = @ir.TypeAttributes::default()
  let exact = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#int"),
    [],
  )
  let modules = Map([])
  modules[@ir.Path::parse("numeric")] = @ir.ModuleSpecification::{
    types: Map::from_array([
      (
        @ir.Name::parse("sdk-extension"),
        @ir.Documented::{
          doc: Some("Versioned MoonBit numeric SDK provenance marker"),
          value: @ir.TypeSpecification::{
            annotations: [],
            body: @ir.TypeSpecificationBody::OpaqueTypeSpecification([]),
          },
        },
      ),
    ]),
    values: Map([]),
    doc: None,
    annotations: [],
  }
  let boolean = @ir.Type::Reference(
    attrs,
    @ir.FQName::parse("morphir/SDK:basics#bool"),
    [],
  )
  let integer_values = Map([])
  for
    (name, arity, boolean_result) in [
      ("add", 2, false),
      ("subtract", 2, false),
      ("multiply", 2, false),
      ("negate", 1, false),
      ("require-budget", 1, false),
      ("equal", 2, true),
      ("not-equal", 2, true),
      ("less-than", 2, true),
      ("less-than-or-equal", 2, true),
      ("greater-than", 2, true),
      ("greater-than-or-equal", 2, true),
    ] {
    integer_values[@ir.Name::parse(name)] = @ir.Documented::{
      doc: Some("Bounded exact MoonBit source integer operation"),
      value: @ir.ValueSpecification::{
        inputs: if arity == 1 {
          [(@ir.Name::parse("value"), exact)]
        } else {
          [(@ir.Name::parse("left"), exact), (@ir.Name::parse("right"), exact)]
        },
        output: if boolean_result {
          boolean
        } else {
          exact
        },
        annotations: [
          @ir.Annotation::Compact(
            @ir.FQName::parse("morphir/moonbit-source:numeric#sdk-extension"),
            Some("morphir-moonbit-source-integer-v1"),
          ),
        ],
      },
    }
  }
  modules[@ir.Path::parse("integer")] = @ir.ModuleSpecification::{
    types: Map([]),
    values: integer_values,
    doc: None,
    annotations: [],
  }
  for
    (module_name, type_name) in [
      ("int16", "int-16"),
      ("int64", "int-64"),
      ("byte", "byte"),
      ("uint16", "uint-16"),
      ("uint32", "uint-32"),
      ("uint64", "uint-64"),
    ] {
    modules[@ir.Path::parse(module_name)] = @ir.ModuleSpecification::{
      types: Map([]),
      values: Map::from_array([
        (
          @ir.Name::parse("normalize"),
          @ir.Documented::{
            doc: Some("MoonBit source-width normalization"),
            value: @ir.ValueSpecification::{
              inputs: [(@ir.Name::parse("value"), exact)],
              output: @ir.Type::Reference(
                attrs,
                @ir.FQName::parse("morphir/SDK:int#" + type_name),
                [],
              ),
              annotations: [
                @ir.Annotation::Compact(
                  @ir.FQName::parse(
                    "morphir/moonbit-source:numeric#sdk-extension",
                  ),
                  Some("morphir-moonbit-source-integer-v1"),
                ),
              ],
            },
          },
        ),
      ]),
      doc: None,
      annotations: [],
    }
  }
  { modules, }
}
