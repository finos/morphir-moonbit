///|
pub(all) struct Props {
  profile : Json
  arguments : String
}

///|
fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(s) => s
    _ => ""
  }
}

///|
fn items(value : Json) -> Array[Json] {
  match value {
    Array(v) => v
    _ => []
  }
}

///|
fn at(
  path : Array[@arguments.Segment],
  segment : @arguments.Segment,
) -> Array[@arguments.Segment] {
  let next = path.copy()
  next.push(segment)
  next
}

///|
fn scalar(
  value : Json,
  path : Array[@arguments.Segment],
  label : String,
  kind : String,
  emit : @cmd.Emit[@arguments.Edit],
) -> @html.Html {
  @html.label(class="argument-field", [
    @html.span(class="argument-field-label", @html.strong(label)),
    @html.input(
      inputmode=if kind == "float" { "decimal" } else { "text" },
      attrs=@html.Attrs::build()
        .aria_label(label)
        .value_prop(@arguments.scalar_text(value)),
      on_input=emit.map(s => @arguments.Scalar(path, kind, s)),
    ),
  ])
}

///|
fn value_field(
  tpe : Json,
  value : Json,
  definitions : Array[Json],
  path : Array[@arguments.Segment],
  label : String,
  emit : @cmd.Emit[@arguments.Edit],
) -> @html.Html {
  let kind = text(tpe, "type")
  if kind == "int" {
    return scalar(
      field(value, "value"),
      at(path, @arguments.Field("value")),
      label,
      "int",
      emit,
    )
  }
  if kind == "bool" {
    return @html.label(class="argument-field", [
      @html.strong(label),
      @html.select(
        attrs=@html.Attrs::build()
          .aria_label(label)
          .value_prop(@arguments.scalar_text(field(value, "value"))),
        on_change=emit.map(s => {
          @arguments.Scalar(at(path, @arguments.Field("value")), "bool", s)
        }),
        [
          @html.option(
            value="false",
            selected=field(value, "value") == Json::boolean(false),
            "false",
          ),
          @html.option(
            value="true",
            selected=field(value, "value") == Json::boolean(true),
            "true",
          ),
        ],
      ),
    ])
  }
  if kind == "unit" {
    return @html.div(class="argument-unit", [
      @html.strong(label),
      @html.code("() · no value required"),
    ])
  }
  let contents : Array[@html.Html] = [
    @html.legend([@html.strong(label), @html.code(kind)]),
  ]
  match kind {
    "decimal" => {
      contents.push(
        scalar(
          field(value, "coefficient"),
          at(path, @arguments.Field("coefficient")),
          label + ".coefficient",
          "int",
          emit,
        ),
      )
      contents.push(
        scalar(
          field(value, "exponent"),
          at(path, @arguments.Field("exponent")),
          label + ".exponent",
          "float",
          emit,
        ),
      )
      contents.push(
        @html.p(class="small muted", "Exact value = coefficient × 10^exponent"),
      )
    }
    "float64" => {
      let bits_path = at(path, @arguments.Field("bits"))
      contents.push(
        @html.label(class="argument-field", [
          @html.strong(label + ".number"),
          @html.input(
            inputmode="decimal",
            attrs=@html.Attrs::build()
              .aria_label(label + ".number")
              .value_prop(@arguments.float64_text(value)),
            on_input=emit.map(s => @arguments.Float64(bits_path, s)),
          ),
        ]),
      )
      contents.push(
        scalar(field(value, "bits"), bits_path, label + ".bits", "int", emit),
      )
      contents.push(
        @html.p(
          class="small muted",
          "Enter a finite number or edit the unsigned 64-bit pattern to preserve signed zero, infinities or NaN payloads.",
        ),
      )
    }
    "text" | "character" => {
      let units_path = at(path, @arguments.Field("units"))
      match @arguments.unicode_text(value) {
        Some(s) =>
          contents.push(
            @html.label(class="argument-field", [
              @html.strong(label + ".text"),
              @html.textarea(
                rows=1,
                attrs=@html.Attrs::build()
                  .aria_label(label + ".text")
                  .value_prop(s),
                on_input=emit.map(s => @arguments.TextUnits(units_path, s)),
                "",
              ),
            ]),
          )
        None =>
          contents.push(
            @html.p(
              class="small muted",
              "This value contains isolated UTF-16 units or an unfinished unit. Edit the units below.",
            ),
          )
      }
      let controls = []
      for i, unit in items(field(value, "units")) {
        let address = label + ".units[" + (i + 1).to_string() + "]"
        controls.push(
          @html.div(class="argument-list-item", [
            scalar(
              unit,
              at(units_path, @arguments.Index(i)),
              address,
              "float",
              emit,
            ),
            @html.button(
              class="secondary argument-remove",
              attrs=@html.Attrs::build().aria_label("Remove " + address),
              on_click=emit(@arguments.Remove(units_path, i)),
              "Remove",
            ),
          ]),
        )
      }
      controls.push(
        @html.button(
          class="secondary",
          attrs=@html.Attrs::build().aria_label("Add unit to " + label),
          on_click=emit(@arguments.Append(units_path, Json::number(0))),
          "Add UTF-16 unit",
        ),
      )
      contents.push(
        @html.details(open=@arguments.unicode_text(value) == None, [
          @html.summary("UTF-16 units"),
          @html.div(class="argument-fields", controls),
        ]),
      )
    }
    "record" => {
      let types = items(field(tpe, "fields"))
      for i, v in items(field(value, "fields")) {
        let name = text(v, "name")
        let t = types.iter().find_first(t => text(t, "name") == name).unwrap()
        let child_path = at(
          at(at(path, @arguments.Field("fields")), @arguments.Index(i)),
          @arguments.Field("value"),
        )
        contents.push(
          value_field(
            field(t, "type"),
            field(v, "value"),
            definitions,
            child_path,
            label + "." + name,
            emit,
          ),
        )
      }
    }
    "list" | "tuple" => {
      let types = items(field(tpe, "items"))
      let child_path = at(path, @arguments.Field("items"))
      for i, v in items(field(value, "items")) {
        let t = if kind == "list" { field(tpe, "item") } else { types[i] }
        let address = label + "[" + (i + 1).to_string() + "]"
        contents.push(
          value_field(
            t,
            v,
            definitions,
            at(child_path, @arguments.Index(i)),
            address,
            emit,
          ),
        )
        if kind == "list" {
          contents.push(
            @html.button(
              class="secondary argument-remove",
              attrs=@html.Attrs::build().aria_label("Remove " + address),
              on_click=emit(@arguments.Remove(child_path, i)),
              "Remove",
            ),
          )
        }
      }
      if kind == "list" {
        let default_value = @arguments.typed_default(
          field(tpe, "item"),
          definitions,
        ) catch {
          _ => Json::null()
        }
        contents.push(
          @html.button(
            class="secondary",
            disabled=default_value == Json::null(),
            attrs=@html.Attrs::build().aria_label("Add item to " + label),
            on_click=emit(@arguments.Append(child_path, default_value)),
            "Add item",
          ),
        )
        if default_value == Json::null() {
          contents.push(
            @html.p(
              class="small muted",
              "This item has no finite default. Add it through JSON inputs.",
            ),
          )
        }
      }
    }
    "maybe" | "result" | "custom" => {
      let variants : Array[(String, Array[Json])] = if kind == "maybe" {
        [("nothing", []), ("just", [field(tpe, "item")])]
      } else if kind == "result" {
        [("ok", [field(tpe, "ok")]), ("err", [field(tpe, "err")])]
      } else {
        let d = definitions
          .iter()
          .find_first(d => text(d, "name") == text(tpe, "name"))
          .unwrap()
        items(field(d, "constructors")).map(c => {
          (text(c, "name"), items(field(c, "inputs")))
        })
      }
      let tag = text(value, if kind == "custom" { "tag" } else { "case" })
      let choices = variants.map(variant => {
        let default_value = try {
          let children = variant.1.map(t => {
            @arguments.typed_default(t, definitions)
          })
          if kind == "custom" {
            (
              {
                "type": "custom",
                "owner": text(tpe, "name"),
                "tag": variant.0,
                "items": children,
              } : Json)
          } else if children.is_empty() {
            ({ "type": kind, "case": variant.0 } : Json)
          } else {
            ({ "type": kind, "case": variant.0, "value": children[0] } : Json)
          }
        } catch {
          _ => Json::null()
        }
        (variant.0, default_value)
      })
      contents.push(
        @html.label(class="argument-field", [
          @html.strong(if kind == "custom" { "Constructor" } else { "Case" }),
          @html.select(
            attrs=@html.Attrs::build()
              .aria_label(
                label +
                (if kind == "custom" { " constructor" } else { " case" }),
              )
              .value_prop(tag),
            on_change=emit.map(tag => {
              @arguments.Set(
                path,
                choices.iter().find_first(c => c.0 == tag).unwrap().1,
              )
            }),
            choices.map(c => {
              @html.option(
                value=c.0,
                selected=c.0 == tag,
                disabled=c.1 == Json::null(),
                c.0,
              )
            }),
          ),
        ]),
      )
      if choices.any(c => c.1 == Json::null()) {
        contents.push(
          @html.p(
            class="small muted",
            "Cases without a finite default can be entered through JSON inputs.",
          ),
        )
      }
      let types = variants.iter().find_first(v => v.0 == tag).unwrap().1
      for i, t in types {
        let child_path = if kind == "custom" {
          at(at(path, @arguments.Field("items")), @arguments.Index(i))
        } else {
          at(path, @arguments.Field("value"))
        }
        let child = if kind == "custom" {
          items(field(value, "items"))[i]
        } else {
          field(value, "value")
        }
        contents.push(
          value_field(
            t,
            child,
            definitions,
            child_path,
            label + "." + (i + 1).to_string(),
            emit,
          ),
        )
      }
    }
    _ => ()
  }
  @html.fieldset(class="argument-group", contents)
}

///|
pub fn view(props : Props, emit : @cmd.Emit[@arguments.Edit]) -> @html.Html {
  match @arguments.typed_form_error(props.profile, props.arguments) {
    Some(error) =>
      @html.div(class="argument-shape-error", [
        @html.p(error),
        @html.p(
          class="small muted",
          "Use JSON inputs to repair this document, or explicitly reset its values.",
        ),
        @html.button(
          class="secondary",
          on_click=emit(@arguments.Set([], field(props.profile, "default"))),
          "Reset inputs",
        ),
      ])
    None => {
      let values = items(
        @json.parse(props.arguments) catch {
          _ => Json::null()
        },
      )
      let definitions = items(field(props.profile, "definitions"))
      @html.div(
        class="argument-fields",
        items(field(props.profile, "inputs")).mapi((i, input) => {
          value_field(
            field(input, "type"),
            values[i],
            definitions,
            [@arguments.Index(i)],
            text(input, "label"),
            emit,
          )
        }),
      )
    }
  }
}
