///|
let cache : Ref[@ir.PackageSpecification?] = Ref(None)

///|
pub fn sdk_package_name() -> @ir.PackageName {
  @ir.Path::parse("morphir/SDK") catch {
    _ => panic()
  }
}

///|
pub fn sdk_specification() -> @ir.PackageSpecification {
  match cache.val {
    Some(spec) => spec
    None => {
      let file = @ir_json.read(sdk_json) catch {
        _ => abort("finos/morphir-sdk-spec: sdk_data.mbt does not decode")
      }
      guard file.distribution is Specs(_, _, spec) else {
        abort("finos/morphir-sdk-spec: expected a Specs distribution")
      }
      cache.val = Some(spec)
      spec
    }
  }
}
