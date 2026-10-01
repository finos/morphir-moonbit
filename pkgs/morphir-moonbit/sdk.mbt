///|
fn sdk_constructor(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  match (name.to_canonical(), expected) {
    ("morphir/SDK:maybe#nothing", Optional(_)) => "None"
    ("morphir/SDK:maybe#just", Arrow(a, Optional(b))) if a == b =>
      curry_source(ctx, [("value", a)], Optional(b), "Some(value)")
    ("morphir/SDK:result#ok", Arrow(a, Outcome(b, e))) if a == b =>
      curry_source(ctx, [("value", a)], Outcome(b, e), "Ok(value)")
    ("morphir/SDK:result#err", Arrow(e, Outcome(a, b))) if e == b =>
      curry_source(ctx, [("value", e)], Outcome(a, b), "Err(value)")
    _ =>
      raise Invalid(
        "moonbit.unresolved_constructor",
        context,
        name.to_canonical(),
      )
  }
}

///|
fn sdk_reference(
  ctx : Lowering,
  name : @ir.FQName,
  expected : Lowered,
  context : String,
) -> String raise {
  let inputs = []
  let mut result = expected
  while result is Arrow(a, b) {
    inputs.push(a)
    result = b
  }
  let args = Array::makei(inputs.length(), i => ("a" + i.to_string(), inputs[i]))
  let canonical = name.to_canonical()
  let int = Atom(Scalar::Integer)
  let dec = Atom(Scalar::Decimal)
  let float = Atom(Scalar::Float)
  let bool = Atom(Scalar::Boolean)
  let mut call = ""
  let module_name = name.module_name.to_canonical()
  let binding = name.local_name.to_canonical()
  fn require(signature : Array[Lowered], output : Lowered) -> Unit raise {
    if inputs != signature || result != output {
      raise Invalid("moonbit.sdk_signature", context, canonical)
    }
  }
  fn native(module_name : String, function : String) -> String {
    ctx.imports[module_name] = true
    "@" +
    module_name +
    "." +
    function +
    "(" +
    args.map(p => p.0).join(", ") +
    ")"
  }
  match (module_name, binding) {
    ("basics", "add" | "subtract" | "multiply") => {
      let t = if inputs == [int, int] { int } else { float }
      require([t, t], t)
      call = native(
        "basics",
        binding + (if t == int { "_int" } else { "_float" }),
      )
    }
    ("basics", "integer-divide" | "power" | "mod-by" | "remainder-by") => {
      require([int, int], int)
      call = native(
        "basics",
        match binding {
          "power" => "power_int"
          "integer-divide" => "integer_divide"
          "mod-by" => "mod_by"
          _ => "remainder_by"
        },
      )
    }
    ("basics", "divide") => {
      require([float, float], float)
      call = native("basics", "divide")
    }
    ("basics", "negate" | "abs") => {
      let t = if inputs == [int] { int } else { float }
      require([t], t)
      call = native(
        "basics",
        binding + (if t == int { "_int" } else { "_float" }),
      )
    }
    ("basics", "not") => {
      require([bool], bool)
      call = "!a0"
    }
    ("basics", "and" | "or" | "xor") => {
      require([bool, bool], bool)
      call = native("basics", binding + "_")
    }
    ("basics", "identity") if inputs.length() == 1 && inputs[0] == result =>
      call = "a0"
    ("basics", "always") if inputs.length() == 2 && inputs[0] == result =>
      call = "a0"
    ("basics", "to-float") => {
      require([int], float)
      call = native("basics", "to_float")
    }
    ("basics", "round" | "floor" | "ceiling" | "truncate") => {
      require([float], int)
      call = native("basics", binding)
    }
    (
      "basics",
      "equal"
      | "not-equal"
      | "less-than"
      | "greater-than"
      | "less-than-or-equal"
      | "greater-than-or-equal",
    ) if inputs.length() == 2 && inputs[0] == inputs[1] => {
      let t = inputs[0]
      if ![int, float, bool, Atom(Scalar::Text), Atom(Scalar::Character)].contains(
          t,
        ) {
        raise Invalid(
          "moonbit.unsupported_sdk", context, "Comparison requires an audited scalar instance",
        )
      }
      require([t, t], bool)
      if t == Atom(Scalar::Text) && !["equal", "not-equal"].contains(binding) {
        if binding == "less-than" || binding == "greater-than" {
          call = native("basics", binding.replace(old="-", new="_") + "_string")
        } else {
          ctx.imports["basics"] = true
          call = if binding == "less-than-or-equal" {
            "!@basics.greater_than_string(a0, a1)"
          } else {
            "!@basics.less_than_string(a0, a1)"
          }
        }
      } else {
        call = native("basics", binding.replace(old="-", new="_"))
      }
    }
    ("decimal", "add" | "sub" | "mul") => {
      require([dec, dec], dec)
      call = native("decimal", binding)
    }
    ("decimal", "div") => {
      require([dec, dec], Optional(dec))
      call = native("decimal", "div")
    }
    ("decimal", "negate" | "abs" | "truncate" | "round") => {
      require([dec], dec)
      call = native("decimal", binding)
    }
    ("decimal", "eq" | "neq" | "gt" | "gte" | "lt" | "lte") => {
      require([dec, dec], bool)
      call = native("decimal", binding)
    }
    ("decimal", "from-int") => {
      require([int], dec)
      call = native("decimal", "from_int")
    }
    ("decimal", "zero" | "one" | "minus-one") => {
      require([], dec)
      call = native("decimal", binding.replace(old="-", new="_"))
    }
    ("list", "map") => {
      guard inputs is [Arrow(a, b), Sequence(c)] &&
        result is Sequence(d) &&
        a == c &&
        b == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("list", "map")
    }
    ("list", "filter") => {
      guard inputs is [Arrow(a, b), Sequence(c)] &&
        result is Sequence(d) &&
        a == c &&
        b == bool &&
        c == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("list", "filter")
    }
    ("list", "sum" | "product") => {
      require([Sequence(int)], int)
      call = native("list", binding)
    }
    ("list", "length") if inputs.length() == 1 && inputs[0] is Sequence(_) => {
      require(inputs, int)
      ctx.imports["integer"] = true
      call = "@integer.from_int(" + native("list", "length") + ")"
    }
    ("list", "reverse") if inputs.length() == 1 &&
      inputs[0] is Sequence(_) &&
      result == inputs[0] => call = native("list", "reverse")
    ("list", "append") if inputs.length() == 2 &&
      inputs[0] is Sequence(_) &&
      inputs[0] == inputs[1] &&
      result == inputs[0] => call = native("list", "append")
    ("list", "foldl" | "foldr") => {
      guard inputs is [Arrow(a, Arrow(b, c)), d, Sequence(e)] &&
        a == e &&
        b == c &&
        c == d &&
        result == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      ctx.imports["list"] = true
      call = "@list." +
        binding +
        "(fn(value, state) raise @sdk.SdkError { a0(value)(state) }, a1, a2)"
    }
    ("maybe", "with-default") => {
      guard inputs is [a, Optional(b)] && a == b && result == a else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("maybe", "with_default")
    }
    ("maybe", "map") => {
      guard inputs is [Arrow(a, b), Optional(c)] &&
        result is Optional(d) &&
        a == c &&
        b == d else {
        raise Invalid("moonbit.sdk_signature", context, canonical)
      }
      call = native("maybe", "map")
    }
    _ => raise Invalid("moonbit.unsupported_sdk", context, canonical)
  }
  curry_source(ctx, args, result, call)
}
