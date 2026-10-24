///|
pub fn[A, B] and_then(f : (A) -> B? raise?, value : A?) -> B? raise? {
  match value {
    Some(a) => f(a)
    None => None
  }
}

///|
pub fn[A, B] map(f : (A) -> B raise?, value : A?) -> B? raise? {
  match value {
    Some(a) => Some(f(a))
    None => None
  }
}

///|
pub fn[A] with_default(fallback : A, value : A?) -> A {
  match value {
    Some(a) => a
    None => fallback
  }
}

///|
pub fn[A] has_value(value : A?) -> Bool {
  value is Some(_)
}

///|
pub fn[A, B, Z] map2(f : (A, B) -> Z raise?, v0 : A?, v1 : B?) -> Z? raise? {
  match (v0, v1) {
    (Some(a0), Some(a1)) => Some(f(a0, a1))
    _ => None
  }
}

///|
pub fn[A, B, C, Z] map3(
  f : (A, B, C) -> Z raise?,
  v0 : A?,
  v1 : B?,
  v2 : C?,
) -> Z? raise? {
  match (v0, v1, v2) {
    (Some(a0), Some(a1), Some(a2)) => Some(f(a0, a1, a2))
    _ => None
  }
}

///|
pub fn[A, B, C, D, Z] map4(
  f : (A, B, C, D) -> Z raise?,
  v0 : A?,
  v1 : B?,
  v2 : C?,
  v3 : D?,
) -> Z? raise? {
  match (v0, v1, v2, v3) {
    (Some(a0), Some(a1), Some(a2), Some(a3)) => Some(f(a0, a1, a2, a3))
    _ => None
  }
}

///|
pub fn[A, B, C, D, E, Z] map5(
  f : (A, B, C, D, E) -> Z raise?,
  v0 : A?,
  v1 : B?,
  v2 : C?,
  v3 : D?,
  v4 : E?,
) -> Z? raise? {
  match (v0, v1, v2, v3, v4) {
    (Some(a0), Some(a1), Some(a2), Some(a3), Some(a4)) =>
      Some(f(a0, a1, a2, a3, a4))
    _ => None
  }
}
