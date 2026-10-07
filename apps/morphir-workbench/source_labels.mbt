///|
fn ion_field(value : @ion.IonValue, name : String) -> @ion.IonValue {
  match value.kind() {
    Struct(fields) => {
      for field in fields {
        if field.name().text() == Some(name) {
          return field.value()
        }
      }
      @ion.IonValue::untyped_null()
    }
    _ => @ion.IonValue::untyped_null()
  }
}

///|
fn ion_name(value : @ion.IonValue) -> String {
  match ion_field(value, "name").kind() {
    String(name) => name
    _ => ""
  }
}

///|
/// Use source spelling only in UI labels. Canonical IR identities stay untouched.
fn source_ui(
  fields : Array[(String, Json)],
  output : @moonbit_frontend.Output,
) -> Unit {
  let origin = output.metadata[0].data
  let name = ion_name(ion_field(origin, "declaration"))
  let parameters = match ion_field(origin, "parameters").kind() {
    List(values) => values.map(ion_name)
    _ => []
  }
  for i, (key, value) in fields {
    if key == "nodes" && value is Array(nodes) {
      fields[i] = (
        key,
        Json::array(
          nodes.map(node => {
            if node is Object(data) &&
              data.get("id") == Some(@wire.text(output.entry.to_canonical())) {
              let data = data.copy()
              let original = node_text(node, "label")
              data["label"] = @wire.text(name)
              data["signature"] = @wire.text(
                node_text(node, "signature").replace_all(old=original, new=name),
              )
              if data.get("inputs") is Some(Array(inputs)) {
                data["inputs"] = Json::array(
                  inputs.mapi((index, input) => {
                    if input is Object(row) {
                      let row = row.copy()
                      row["name"] = @wire.text(
                        parameters
                        .get(index)
                        .unwrap_or(node_text(input, "name")),
                      )
                      Json::object(row)
                    } else {
                      input
                    }
                  }),
                )
              }
              Json::object(data)
            } else {
              node
            }
          }),
        ),
      )
    } else if key == "typedEvaluations" &&
      value is Object(profiles) &&
      profiles.get("entries") is Some(Object(entries)) &&
      entries.get(output.entry.to_canonical()) is Some(Object(profile)) &&
      profile.get("inputs") is Some(Array(inputs)) {
      let profile = profile.copy()
      profile["inputs"] = Json::array(
        inputs.mapi((index, input) => {
          if input is Object(row) {
            let row = row.copy()
            row["label"] = @wire.text(
              parameters.get(index).unwrap_or(node_text(input, "label")),
            )
            Json::object(row)
          } else {
            input
          }
        }),
      )
      let entries = entries.copy()
      entries[output.entry.to_canonical()] = Json::object(profile)
      fields[i] = (key, @wire.obj([("entries", Json::object(entries))]))
    }
  }
}
