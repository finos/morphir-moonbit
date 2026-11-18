///|
/// Schema-1 compile results describe the product published by this transaction.
pub(all) struct CompileRecordOptions {
  explicit_selection : Bool
  tree_product : String?
}

///|
priv struct CompilePublication {
  before : (String, Array[(String, String)]) -> Unit raise
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
