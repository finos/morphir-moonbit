///|
/// The manifest is authoritative for public execution boundaries. Importing an
/// unsupported model still succeeds and leaves the local Scheme mode available.
fn typed_profiles(file : @ir.IRFile) -> Json {
  try {
    let library = @moonbit.generate(@moonbit.Input::new("workbench", file))
    let definitions = library.invocation_types
    let profiles = library.invocations.map(entry => {
      let (defaults, default_reason) = (
        Json::array(
          entry.inputs.map(t => typed_default(t, definitions, 0, Ref(200))),
        ),
        "",
      ) catch {
        _ =>
          (
            Json::array([]),
            "No finite default was found. Enter tagged values in parameter order.",
          )
      }
      let names = match evaluation_definitions(file).get(entry.fqname) {
        Some(ExpressionBody(inputs, _, _)) => inputs.map(p => display_name(p.0))
        _ => []
      }
      let profile : Json = {
        "supported": true,
        "default": defaults,
        "defaultReason": default_reason,
        "inputs": entry.inputs.mapi((i, t) => {
          (
            {
              "label": names.get(i).unwrap_or("Argument " + (i + 1).to_string()),
              "type": t.to_json(),
            } : Json)
        }),
        "output": entry.output.to_json(),
        "definitions": definitions.map(d => {
          (
            {
              "name": d.name,
              "constructors": d.constructors.map(c => {
                (
                  {
                    "name": c.name,
                    "inputs": c.inputs.map(@protocol.ValueType::to_json),
                  } : Json)
              }),
            } : Json)
        }),
      }
      (entry.fqname, profile)
    })
    @wire.obj([("entries", @wire.obj(profiles))])
  } catch {
    @moonbit.Invalid(code, _, detail) =>
      @wire.obj([("reason", @wire.text(code + ": " + detail))])
  }
}

///|
fn typed_default(
  tpe : @protocol.ValueType,
  definitions : Array[@protocol.CustomType],
  depth : Int,
  budget : Ref[Int],
) -> Json raise {
  budget.val -= 1
  if depth > 24 || budget.val <= 0 {
    raise @protocol.Invalid(
      "No finite default; enter tagged arguments manually",
    )
  }
  match tpe {
    Int => { "type": "int", "value": "0" }
    Bool => { "type": "bool", "value": false }
    Unit => { "type": "unit" }
    Decimal => { "type": "decimal", "coefficient": "0", "exponent": 0 }
    Float64 => { "type": "float64", "bits": "0" }
    Text => { "type": "text", "units": [] }
    Character => { "type": "character", "units": [97] }
    Sequence(_) => { "type": "list", "items": [] }
    Product(types) =>
      {
        "type": "tuple",
        "items": types.map(t => typed_default(t, definitions, depth + 1, budget)),
      }
    Record(fields) =>
      {
        "type": "record",
        "fields": fields.map(p => {
          (
            {
              "name": p.0,
              "value": typed_default(p.1, definitions, depth + 1, budget),
            } : Json)
        }),
      }
    Optional(_) => { "type": "maybe", "case": "nothing" }
    Outcome(ok, _) =>
      {
        "type": "result",
        "case": "ok",
        "value": typed_default(ok, definitions, depth + 1, budget),
      }
    Custom(name) => {
      guard definitions.filter(d => d.name == name).get(0) is Some(d) else {
        raise @protocol.Invalid("execution.unresolved_custom_type")
      }
      // Prefer a nullary variant, which also terminates recursive types.
      let choices = d.constructors.copy()
      choices.sort_by((a, b) => a.inputs.length().compare(b.inputs.length()))
      for c in choices {
        try {
          return {
            "type": "custom",
            "owner": name,
            "tag": c.name,
            "items": c.inputs.map(t => {
              typed_default(t, definitions, depth + 1, budget)
            }),
          }
        } catch {
          _ => ()
        }
      }
      raise @protocol.Invalid(
        "No finite default; enter tagged arguments manually",
      )
    }
    Function => raise @protocol.Invalid("execution.boundary_function")
  }
}

///|
fn evaluate_typed(file : @ir.IRFile, request : Json) -> Json raise {
  let raw = @wire.array(@wire.field(request, "arguments"))
  let entry = @wire.string(@wire.field(request, "entry"))
  // Decode and validate the published profile before entering the runtime.
  let suite = @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [{ "id": "workbench", "entry": entry, "arguments": raw }],
  })
  // The public decoder enforces the encoded byte budget too.
  ignore(@protocol.Suite::decode(suite.encode("json"), "json"))
  let unit = @data.IRUnit::new("workbench", file)
  let plan = @typed_engine.plan(unit, suite)
  let manifest = plan.library.invocations.filter(e => e.fqname == entry)[0]
  let evaluator = @typed_engine.Evaluator::scheme()
  let value = (evaluator.evaluate)(
    unit,
    suite.calls[0],
    manifest.output,
    plan.library.invocation_types,
  )
  let canonical = value.to_json()
  let tree = typed_result_node(canonical, 0, Ref(500))
  @wire.obj([
    ("success", Json::boolean(true)),
    ("typed", canonical),
    ("structured", tree),
    ("value", @wire.text(canonical.stringify())),
    ("profile", @wire.text(evaluator.profile)),
    (
      "outcome",
      @wire.text(if value is ModelError(_) { "model-error" } else { "value" }),
    ),
  ])
}

///|
/// Presentation is bounded independently of the lossless canonical result.
fn typed_result_node(value : Json, depth : Int, budget : Ref[Int]) -> Json {
  fn omitted() -> Json {
    { "kind": "truncated", "text": "Result display limit reached" }
  }
  if budget.val <= 0 {
    return omitted()
  }
  budget.val -= 1
  if depth > 32 {
    return omitted()
  }
  let kind = node_text(value, "type")
  fn children(values : Array[Json]) -> Array[Json] {
    let result = []
    for child in values {
      if budget.val <= 0 {
        result.push(omitted())
        break
      }
      result.push(typed_result_node(child, depth + 1, budget))
    }
    result
  }
  match kind {
    "list" | "tuple" =>
      {
        "kind": kind,
        "items": children(
          @wire.array(@wire.field(value, "items")) catch {
            _ => []
          },
        ),
      }
    "record" => {
      let fields : Array[Json] = []
      let entries = @wire.array(@wire.field(value, "fields")) catch { _ => [] }
      for field in entries {
        if budget.val <= 0 {
          fields.push({ "name": "…", "value": omitted() })
          break
        }
        fields.push({
          "name": node_text(field, "name"),
          "value": typed_result_node(
            @wire.field(field, "value") catch {
              _ => Json::null()
            },
            depth + 1,
            budget,
          ),
        })
      }
      { "kind": "record", "fields": fields }
    }
    "custom" =>
      {
        "kind": "constructor",
        "tag": node_text(value, "owner") + " / " + node_text(value, "tag"),
        "items": children(
          @wire.array(@wire.field(value, "items")) catch {
            _ => []
          },
        ),
      }
    "maybe" | "result" => {
      let values = match (@wire.optional(value, "value") catch { _ => None }) {
        Some(v) => [v]
        None => []
      }
      {
        "kind": "constructor",
        "tag": kind + " / " + node_text(value, "case"),
        "items": children(values),
      }
    }
    _ => {
      let text = if kind == "int" {
        node_text(value, "value")
      } else {
        value.stringify()
      }
      if text.length() > 16384 {
        omitted()
      } else {
        { "kind": kind, "text": text }
      }
    }
  }
}
