///|
pub(all) enum Access {
  Public
  Private
} derive(Eq, Debug)

///|
pub(all) struct AccessControlled[T] {
  access : Access
  value : T
} derive(Eq, Debug)

///|
pub(all) struct Documented[T] {
  doc : String?
  value : T
} derive(Eq, Debug)

///|
/// JSON-shaped extension data. Number lexemes never pass through a floating-point value.
/// This is a data model, not a parser; codecs must validate number lexemes.
pub(all) enum Data {
  Null
  Boolean(Bool)
  Number(String)
  Text(String)
  Array(Array[Data])
  Object(Map[String, Data])
} derive(Eq, Debug)
