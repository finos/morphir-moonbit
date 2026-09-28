///|
/// Inspect formatVersion before decoding a version-specific model.
pub fn from_json(json : Json) -> @model.IRFile raise {
  let version = @wire.read_version(@wire.field(json, "formatVersion"))
  version.check_supported()
  match version.major {
    1U => @model.V1(@v1.from_json(json))
    2U => @model.V2(@v2.from_json(json))
    3U => @model.V3(@v3.from_json(json))
    4U => @model.V4(@v4.from_json(json))
    _ =>
      raise @wire.Invalid(
        "unsupported_format_version",
        version.to_release_string(),
      )
  }
}

///|
pub fn to_json(file : @model.IRFile) -> Json raise {
  match file {
    V1(file) => @v1.to_json(file)
    V2(file) => @v2.to_json(file)
    V3(file) => @v3.to_json(file)
    V4(file) => @v4.to_json(file)
  }
}

///|
/// Read without implicitly migrating the file.
pub fn read(text : String) -> @model.IRFile raise {
  from_json(@wire.parse(text))
}

///|
/// Write using the file's own format version.
pub fn write(file : @model.IRFile) -> String raise {
  to_json(file).stringify()
}
