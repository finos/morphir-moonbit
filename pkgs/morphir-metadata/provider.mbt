///|
fn string_dict(tpe : @ir.Type) -> Bool {
  guard tpe is Reference(_, name, args) &&
    name.to_canonical() == "morphir/SDK:dict#dict" &&
    args.length() == 2 else {
    return false
  }
  args.all(t => {
    t is Reference(_, n, ps) &&
    n.to_canonical() == "morphir/SDK:string#string" &&
    ps.is_empty()
  })
}

///|
fn validate_provider(
  predicate : String,
  restored : RestoredLibrary,
  capabilities : Capabilities,
) -> String raise {
  if !digest(restored.revision) || restored.format != "4.1.0" {
    raise Invalid(
      "metadata.invalid_provider_identity", predicate, "Restore the exact authenticated morphir/naming 4.1.0 Library and supply its SHA-256 revision",
    )
  }
  let native = address(restored.document)
  if native.package_name.to_canonical() != "morphir/naming" ||
    native.format != restored.format ||
    native.fragment != "/distribution" ||
    native.revision != Some("sha256:" + restored.revision) {
    raise Invalid(
      "metadata.invalid_provider_identity", predicate, "Provider document must identify the freshly restored, revision-pinned Library",
    )
  }
  let (_, requested) = declaration(predicate)
  if requested.revision is Some(r) && r != "sha256:" + restored.revision {
    raise Invalid(
      "metadata.provider_revision_mismatch", predicate, "Restore the revision requested by this predicate URI",
    )
  }
  guard restored.core.distribution is Library(package_name, _, definition) &&
    package_name.to_canonical() == "morphir/naming" else {
    raise Invalid(
      "metadata.invalid_provider_declaration", predicate, "The provider must be a Library with public value definitions, not Specs",
    )
  }
  guard definition.modules.get(@ir.Path::parse("naming")) is Some(module_def) &&
    module_def.access == @ir.Access::Public else {
    raise Invalid(
      "metadata.invalid_provider_declaration", predicate, "Expose public module naming",
    )
  }
  guard module_def.value.values.get(@ir.Name::parse("target-names"))
    is Some(entry) &&
    entry.access == @ir.Access::Public else {
    raise Invalid(
      "metadata.invalid_provider_declaration", predicate, "Expose a public target-names value definition",
    )
  }
  guard entry.value.value is ExpressionBody(_, output, _) &&
    output is Record(_, members) &&
    members.length() == 2 else {
    raise Invalid(
      "metadata.invalid_provider_type", predicate, "Declare the closed frontend/backend output record",
    )
  }
  for name in ["frontend", "backend"] {
    guard members.get(@ir.Name::parse(name)) is Some(tpe) && string_dict(tpe) else {
      raise Invalid(
        "metadata.invalid_provider_type", predicate, "Both fields must be Dict String String",
      )
    }
  }
  let context = scoped_context(
    restored.document_metadata,
    Context::new(),
    capabilities,
    restored.document,
  )
  let facts = graph(
    restored.document_metadata,
    context,
    "provider",
    restored.document,
  )
  let declarations = facts.filter(f => {
    f.assertion.subject == TARGET_NAMES_PREDICATE ||
    f.assertion.subject ==
    TARGET_NAMES_PREDICATE.split("#").collect()[0].to_owned() +
    "&rev=sha256:" +
    restored.revision +
    "#/module/naming/value/target-names"
  })
  let stem = "morphir://ir/pkg/morphir/metadata?format=4.1.0#/module/schema/value/"
  fn literals(predicate : String) -> Array[String] raise {
    declarations
    .filter(f => f.assertion.predicate == stem + predicate)
    .map(f => {
      guard f.data is Some(v) && !f.is_json else {
        raise Invalid(
          "metadata.invalid_provider_declaration", predicate, "Schema declarations use literal strings",
        )
      }
      text(v, predicate)
    })
  }
  let roles = literals("subject-role")
  let forms = literals("object-form")
  let interpreters = literals("interpreter")
  if roles.is_empty() ||
    !roles.all(r => r == "ValueDefinition") ||
    forms.is_empty() ||
    !forms.all(f => f == "data") ||
    interpreters.is_empty() ||
    !interpreters.all(i => i == "target-name-language-ids") {
    raise Invalid(
      "metadata.invalid_provider_declaration", predicate, "Declare ValueDefinition, data and target-name-language-ids in the restored provider's own native facts",
    )
  }
  restored.revision
}
