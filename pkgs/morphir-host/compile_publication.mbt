///|
/// Schema-1 compile results describe the product published by this transaction.
pub(all) struct CompileRecordOptions {
  explicit_selection : Bool
  tree_product : String?
}

///|
priv struct CompilePublication {
  before : (String, Array[(String, String?)]) -> Unit raise
  complete : (String) -> Unit raise
  close : () -> Unit
}

///|
fn CompilePublication::inactive() -> CompilePublication {
  { before: (_, _) => (), complete: _ => (), close: () => (), }
}

///|
#cfg(not(target="native"))
fn begin_compile_publication(
  root : String,
  output_root : String,
  destinations : Array[String],
  options : CompileRecordOptions?,
  cancelled : () -> Bool,
) -> CompilePublication {
  ignore((root, output_root, destinations, options, cancelled))
  CompilePublication::inactive()
}

///|
/// Record the version in the staged JSON product, including classic exports.
/// A product without a readable supported IR header has no IR descriptor.
fn compile_artifact_version(artifact : @engine.ContentArtifact) -> String? {
  guard artifact.format == "morphir-json" || artifact.format == "ir-json" else {
    return None
  }
  try {
    let text = match artifact.content {
      Text(text) => text
      Binary(bytes) => @utf8.decode(bytes[:])
    }
    let version = @wire.read_version(
      @wire.field(@wire.parse(text), "formatVersion"),
    )
    version.check_supported()
    let name = if version.minor == 0U && version.patch == 0U {
      version.major.to_string()
    } else {
      version.to_release_string()
    }
    Some("v" + name)
  } catch {
    _ => None
  }
}
