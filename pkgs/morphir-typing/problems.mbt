///|
/// One inference or checking problem.
///
/// `code` is a stable diagnostic code such as `type_mismatch`. `node` is the logical path of the IR node.
/// `expected` and `found` are the two types, when the problem has them.
pub(all) struct InferenceProblem {
  code : String
  node : String
  message : String
  expected : @ir.Type?
  found : @ir.Type?
  source : @ir.SourceLocation?
} derive(Eq, Debug)

///|
pub extend InferenceProblem with Eq::{equal, not_equal}

///|
pub extend InferenceProblem with @debug.Debug::{to_repr}

///|
/// Raised when inference finds one or more problems.
pub(all) suberror InferenceFailed {
  InferenceFailed(Array[InferenceProblem])
} derive(Eq, Debug)

///|
pub extend InferenceFailed with Eq::{equal, not_equal}

///|
pub extend InferenceFailed with @debug.Debug::{to_repr}
