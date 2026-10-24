///|
pub fn[A, B, E] and_then(
  f : (A) -> Result[B, E] raise?,
  value : Result[A, E],
) -> Result[B, E] raise? {
  match value {
    Ok(a) => f(a)
    Err(e) => Err(e)
  }
}

///|
pub fn[A, B, E] map(
  f : (A) -> B raise?,
  value : Result[A, E],
) -> Result[B, E] raise? {
  match value {
    Ok(a) => Ok(f(a))
    Err(e) => Err(e)
  }
}

///|
pub fn[A, E, F] map_error(
  f : (E) -> F raise?,
  value : Result[A, E],
) -> Result[A, F] raise? {
  match value {
    Ok(a) => Ok(a)
    Err(e) => Err(f(e))
  }
}

///|
pub fn[A, E] with_default(fallback : A, value : Result[A, E]) -> A {
  match value {
    Ok(a) => a
    Err(_) => fallback
  }
}

///|
pub fn[A, E] to_maybe(value : Result[A, E]) -> A? {
  match value {
    Ok(a) => Some(a)
    Err(_) => None
  }
}

///|
pub fn[A, E] from_maybe(error : E, value : A?) -> Result[A, E] {
  match value {
    Some(a) => Ok(a)
    None => Err(error)
  }
}

///|
pub fn[A, B, Z, ErrorValue] map2(
  f : (A, B) -> Z raise?,
  v0 : Result[A, ErrorValue],
  v1 : Result[B, ErrorValue],
) -> Result[Z, ErrorValue] raise? {
  match v0 {
    Ok(a0) =>
      match v1 {
        Ok(a1) => Ok(f(a0, a1))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
pub fn[A, B, C, Z, ErrorValue] map3(
  f : (A, B, C) -> Z raise?,
  v0 : Result[A, ErrorValue],
  v1 : Result[B, ErrorValue],
  v2 : Result[C, ErrorValue],
) -> Result[Z, ErrorValue] raise? {
  match v0 {
    Ok(a0) =>
      match v1 {
        Ok(a1) =>
          match v2 {
            Ok(a2) => Ok(f(a0, a1, a2))
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
pub fn[A, B, C, D, Z, ErrorValue] map4(
  f : (A, B, C, D) -> Z raise?,
  v0 : Result[A, ErrorValue],
  v1 : Result[B, ErrorValue],
  v2 : Result[C, ErrorValue],
  v3 : Result[D, ErrorValue],
) -> Result[Z, ErrorValue] raise? {
  match v0 {
    Ok(a0) =>
      match v1 {
        Ok(a1) =>
          match v2 {
            Ok(a2) =>
              match v3 {
                Ok(a3) => Ok(f(a0, a1, a2, a3))
                Err(e) => Err(e)
              }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
pub fn[A, B, C, D, E, Z, ErrorValue] map5(
  f : (A, B, C, D, E) -> Z raise?,
  v0 : Result[A, ErrorValue],
  v1 : Result[B, ErrorValue],
  v2 : Result[C, ErrorValue],
  v3 : Result[D, ErrorValue],
  v4 : Result[E, ErrorValue],
) -> Result[Z, ErrorValue] raise? {
  match v0 {
    Ok(a0) =>
      match v1 {
        Ok(a1) =>
          match v2 {
            Ok(a2) =>
              match v3 {
                Ok(a3) =>
                  match v4 {
                    Ok(a4) => Ok(f(a0, a1, a2, a3, a4))
                    Err(e) => Err(e)
                  }
                Err(e) => Err(e)
              }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}
