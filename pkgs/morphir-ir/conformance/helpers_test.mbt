///|
fn read_version(json : Json) -> @version.FormatVersion raise {
  let version = @wire.read_version(json)
  version.check_supported()
  version
}

///|
#warnings("-unused_error_type")
fn write_unit(value : Unit) -> Json raise {
  @wire.write_unit(value)
}

///|
fn read_unit(value : Json) -> Unit raise {
  @wire.unit(value)
}
