///|
pub const PROFILE : String = "moonbit-model-bool-v1"

///|
pub const PARSER_VERSION : String = "0.4.1"

///|
pub(all) struct Input {
  unit_id : String
  package_name : String
  module_name : String
  source : String
}

///|
pub(all) struct Limits {
  max_bytes : Int
  max_parameters : Int
  max_depth : Int
  max_expressions : Int
} derive(Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  {
    max_bytes: 65536,
    max_parameters: 16,
    max_depth: 64,
    max_expressions: 4096,
  }
}

///|
pub(all) struct Diagnostic {
  code : String
  detail : String
  source : @ir.SourceLocation?
} derive(Debug)

///|
pub(all) suberror FrontendError {
  Invalid(Diagnostic)
} derive(Debug)

///|
pub(all) struct NodeMetadata {
  node_id : String
  data : @ion.IonValue
}

///|
/// Applications adapt this contract to IRUnit without an engine dependency here.
pub(all) struct Output {
  unit_id : String
  ir : @ir.IRFile
  entry : @ir.FQName
  public : Bool
  metadata : Array[NodeMetadata]
  annotations : Array[@ion.SymbolToken]
  provenance : Array[@ion.IonValue]
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend FrontendError with @debug.Debug::{to_repr}
