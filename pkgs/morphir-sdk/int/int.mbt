///|
pub struct Int8 {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int8(n : @integer.Integer) -> Int8? {
  let low = @integer.from_int64(-128L)
  let high = @integer.from_int64(127L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int8(n : Int8) -> @integer.Integer {
  n.value
}

///|
pub struct Int16 {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int16(n : @integer.Integer) -> Int16? {
  let low = @integer.from_int64(-32768L)
  let high = @integer.from_int64(32767L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int16(n : Int16) -> @integer.Integer {
  n.value
}

///|
pub struct Int32 {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int32(n : @integer.Integer) -> Int32? {
  let low = @integer.from_int64(-2147483648L)
  let high = @integer.from_int64(2147483647L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int32(n : Int32) -> @integer.Integer {
  n.value
}

///|
pub struct Int64 {
  value : @integer.Integer
} derive(Eq, Compare, Debug)

///|
pub fn to_int64(n : @integer.Integer) -> Int64? {
  let low = @integer.from_int64(-9223372036854775808L)
  let high = @integer.from_int64(9223372036854775807L)
  if n < low || n > high {
    None
  } else {
    Some({ value: n, })
  }
}

///|
pub fn from_int64(n : Int64) -> @integer.Integer {
  n.value
}

///|
pub extend Int8 with Eq::{equal, not_equal}

///|
pub extend Int8 with @debug.Debug::{to_repr}

///|
pub extend Int8 with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int16 with Eq::{equal, not_equal}

///|
pub extend Int16 with @debug.Debug::{to_repr}

///|
pub extend Int16 with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int32 with Eq::{equal, not_equal}

///|
pub extend Int32 with @debug.Debug::{to_repr}

///|
pub extend Int32 with Compare::{compare, op_lt, op_le, op_gt, op_ge}

///|
pub extend Int64 with Eq::{equal, not_equal}

///|
pub extend Int64 with @debug.Debug::{to_repr}

///|
pub extend Int64 with Compare::{compare, op_lt, op_le, op_gt, op_ge}
