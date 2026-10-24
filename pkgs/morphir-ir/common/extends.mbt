///|
pub extend Name with Eq::{equal, not_equal}

///|
pub extend Name with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Name with Hash::{hash, hash_combine}

///|
pub extend Name with @debug.Debug::{to_repr}

///|
pub extend Path with Eq::{equal, not_equal}

///|
pub extend Path with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Path with Hash::{hash, hash_combine}

///|
pub extend Path with @debug.Debug::{to_repr}

///|
pub extend FQName with Eq::{equal, not_equal}

///|
pub extend FQName with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend FQName with Hash::{hash, hash_combine}

///|
pub extend FQName with @debug.Debug::{to_repr}

///|
pub extend Access with Eq::{equal, not_equal}

///|
pub extend Access with @debug.Debug::{to_repr}

///|
pub extend AccessControlled with Eq::{equal, not_equal}

///|
pub extend AccessControlled with @debug.Debug::{to_repr}

///|
pub extend Documented with Eq::{equal, not_equal}

///|
pub extend Documented with @debug.Debug::{to_repr}

///|
pub extend Data with Eq::{equal, not_equal}

///|
pub extend Data with @debug.Debug::{to_repr}

///|
pub extend NameSegment with Eq::{equal, not_equal}

///|
pub extend NameSegment with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend NameSegment with Hash::{hash, hash_combine}

///|
pub extend NameSegment with @debug.Debug::{to_repr}

///|
pub extend NameError with Eq::{equal, not_equal}

///|
pub extend NameError with @debug.Debug::{to_repr}
