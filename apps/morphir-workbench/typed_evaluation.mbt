///|
/// The manifest is authoritative for public execution boundaries. Importing an
/// unsupported model still succeeds and leaves the local Scheme mode available.
fn typed_profiles(file : @ir.IRFile) -> Json {
  try {
    let library = @moonbit.generate(@moonbit.Input::new("workbench", file))
    let definitions = library.invocation_types
    let registry = definitions.map(d => {
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
    })
    let values = evaluation_definitions(file)
    let profiles = library.invocations.map(entry => {
      let (defaults, default_reason) = (
        Json::array(
          entry.inputs.map(t => @arguments.typed_default(t.to_json(), registry)),
        ),
        "",
      ) catch {
        _ =>
          (
            Json::array([]),
            "No finite default was found. Enter tagged values in parameter order.",
          )
      }
      let names = match values.get(entry.fqname) {
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
        "definitions": registry,
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
