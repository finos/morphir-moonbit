///|
fn sdk_maybe_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name.clamped_view(start="morphir/SDK:maybe#".length()).to_owned()
  match suffix {
    "has-value" => @scheme.Boolean(@sdk_maybe.has_value(sdk_maybe(args[0])))
    "with-default" => @sdk_maybe.with_default(args[0], sdk_maybe(args[1]))
    "map" =>
      sdk_maybe_value(
        @sdk_maybe.map(
          fn(value) raise { sdk_apply(rt, args[0], [value]) },
          sdk_maybe(args[1]),
        ),
      )
    "and-then" =>
      sdk_maybe_value(
        @sdk_maybe.and_then(
          fn(value) raise { sdk_maybe(sdk_apply(rt, args[0], [value])) },
          sdk_maybe(args[1]),
        ),
      )
    "map2" =>
      sdk_maybe_value(
        @sdk_maybe.map2(
          fn(a, b) raise { sdk_apply(rt, args[0], [a, b]) },
          sdk_maybe(args[1]),
          sdk_maybe(args[2]),
        ),
      )
    "map3" =>
      sdk_maybe_value(
        @sdk_maybe.map3(
          fn(a, b, c) raise { sdk_apply(rt, args[0], [a, b, c]) },
          sdk_maybe(args[1]),
          sdk_maybe(args[2]),
          sdk_maybe(args[3]),
        ),
      )
    "map4" =>
      sdk_maybe_value(
        @sdk_maybe.map4(
          fn(a, b, c, d) raise { sdk_apply(rt, args[0], [a, b, c, d]) },
          sdk_maybe(args[1]),
          sdk_maybe(args[2]),
          sdk_maybe(args[3]),
          sdk_maybe(args[4]),
        ),
      )
    "map5" =>
      sdk_maybe_value(
        @sdk_maybe.map5(
          fn(a, b, c, d, e) raise { sdk_apply(rt, args[0], [a, b, c, d, e]) },
          sdk_maybe(args[1]),
          sdk_maybe(args[2]),
          sdk_maybe(args[3]),
          sdk_maybe(args[4]),
          sdk_maybe(args[5]),
        ),
      )
    _ => raise @scheme.Unbound(name)
  }
}

///|
fn sdk_result_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name
    .clamped_view(start="morphir/SDK:result#".length())
    .to_owned()
  match suffix {
    "with-default" => @sdk_result.with_default(args[0], sdk_result(args[1]))
    "to-maybe" => sdk_maybe_value(@sdk_result.to_maybe(sdk_result(args[0])))
    "from-maybe" =>
      sdk_result_value(@sdk_result.from_maybe(args[0], sdk_maybe(args[1])))
    "map" =>
      sdk_result_value(
        @sdk_result.map(
          fn(value) raise { sdk_apply(rt, args[0], [value]) },
          sdk_result(args[1]),
        ),
      )
    "map-error" =>
      sdk_result_value(
        @sdk_result.map_error(
          fn(value) raise { sdk_apply(rt, args[0], [value]) },
          sdk_result(args[1]),
        ),
      )
    "and-then" =>
      sdk_result_value(
        @sdk_result.and_then(
          fn(value) raise { sdk_result(sdk_apply(rt, args[0], [value])) },
          sdk_result(args[1]),
        ),
      )
    "map2" =>
      sdk_result_value(
        @sdk_result.map2(
          fn(a, b) raise { sdk_apply(rt, args[0], [a, b]) },
          sdk_result(args[1]),
          sdk_result(args[2]),
        ),
      )
    "map3" =>
      sdk_result_value(
        @sdk_result.map3(
          fn(a, b, c) raise { sdk_apply(rt, args[0], [a, b, c]) },
          sdk_result(args[1]),
          sdk_result(args[2]),
          sdk_result(args[3]),
        ),
      )
    "map4" =>
      sdk_result_value(
        @sdk_result.map4(
          fn(a, b, c, d) raise { sdk_apply(rt, args[0], [a, b, c, d]) },
          sdk_result(args[1]),
          sdk_result(args[2]),
          sdk_result(args[3]),
          sdk_result(args[4]),
        ),
      )
    "map5" =>
      sdk_result_value(
        @sdk_result.map5(
          fn(a, b, c, d, e) raise { sdk_apply(rt, args[0], [a, b, c, d, e]) },
          sdk_result(args[1]),
          sdk_result(args[2]),
          sdk_result(args[3]),
          sdk_result(args[4]),
          sdk_result(args[5]),
        ),
      )
    _ => raise @scheme.Unbound(name)
  }
}
