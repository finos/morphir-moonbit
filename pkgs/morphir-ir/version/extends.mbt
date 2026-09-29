///|
pub extend FormatVersion with Eq::{equal, not_equal}

///|
pub extend FormatVersion with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend FormatVersion with Hash::{hash, hash_combine}

///|
pub extend FormatVersion with @debug.Debug::{to_repr}

///|
pub extend VersionError with Eq::{equal, not_equal}

///|
pub extend VersionError with @debug.Debug::{to_repr}
