///|
fn sdk_value_list(
  value : @scheme.Value,
) -> @sdk_list.List[@scheme.Value] raise @scheme.SchemeError {
  @sdk_list.from_array(value.to_array())
}

///|
fn sdk_list_value(value : @sdk_list.List[@scheme.Value]) -> @scheme.Value {
  @scheme.list(@sdk_list.to_array(value))
}

///|
fn sdk_list_pair(
  value : @scheme.Value,
) -> (@scheme.Value, @scheme.Value) raise @scheme.SchemeError {
  match value {
    @scheme.Vector([a, b]) => (a, b)
    _ => raise @scheme.Invalid("Expected Morphir pair")
  }
}

///|
fn sdk_list_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name.clamped_view(start="morphir/SDK:list#".length()).to_owned()
  match suffix {
    "singleton" => sdk_list_value(@sdk_list.singleton(args[0]))
    "repeat" => sdk_list_value(@sdk_list.repeat(sdk_int(args[0]), args[1]))
    "range" =>
      sdk_list_value(
        @sdk_list.map(
          exact_integer,
          @sdk_list.range(sdk_integer(args[0]), sdk_integer(args[1])),
        ),
      )
    "cons" => sdk_list_value(@sdk_list.cons(args[0], sdk_value_list(args[1])))
    "map" =>
      sdk_list_value(
        @sdk_list.map(
          fn(value) raise { sdk_apply(rt, args[0], [value]) },
          sdk_value_list(args[1]),
        ),
      )
    "indexed-map" =>
      sdk_list_value(
        @sdk_list.indexed_map(
          fn(index, value) raise {
            sdk_apply(rt, args[0], [
              exact_integer(@integer.from_int(index)),
              value,
            ])
          },
          sdk_value_list(args[1]),
        ),
      )
    "foldl" =>
      @sdk_list.foldl(
        fn(value, acc) raise { sdk_apply(rt, args[0], [value, acc]) },
        args[1],
        sdk_value_list(args[2]),
      )
    "foldr" =>
      @sdk_list.foldr(
        fn(value, acc) raise { sdk_apply(rt, args[0], [value, acc]) },
        args[1],
        sdk_value_list(args[2]),
      )
    "filter" =>
      sdk_list_value(
        @sdk_list.filter(
          fn(value) raise { sdk_bool(sdk_apply(rt, args[0], [value])) },
          sdk_value_list(args[1]),
        ),
      )
    "filter-map" =>
      sdk_list_value(
        @sdk_list.filter_map(
          fn(value) raise { sdk_maybe(sdk_apply(rt, args[0], [value])) },
          sdk_value_list(args[1]),
        ),
      )
    "length" =>
      exact_integer(
        @integer.from_int(@sdk_list.length(sdk_value_list(args[0]))),
      )
    "reverse" => sdk_list_value(@sdk_list.reverse(sdk_value_list(args[0])))
    "member" => {
      sdk_assert_equality_data(args[0], 0)
      let target_has_nan = sdk_contains_nan(args[0], 0)
      @scheme.Boolean(
        @sdk_list.to_array(sdk_value_list(args[1])).any(fn(value) raise {
          sdk_assert_equality_data(value, 0)
          !target_has_nan &&
          !sdk_contains_nan(value, 0) &&
          rt.equal_values(
            sdk_normalize_equality(args[0], 0),
            sdk_normalize_equality(value, 0),
          )
        }),
      )
    }
    "all" =>
      @scheme.Boolean(
        @sdk_list.all(
          fn(value) raise { sdk_bool(sdk_apply(rt, args[0], [value])) },
          sdk_value_list(args[1]),
        ),
      )
    "any" =>
      @scheme.Boolean(
        @sdk_list.any(
          fn(value) raise { sdk_bool(sdk_apply(rt, args[0], [value])) },
          sdk_value_list(args[1]),
        ),
      )
    "maximum" | "minimum" => {
      let values = @sdk_list.to_array(sdk_value_list(args[0]))
      if values.is_empty() {
        return sdk_maybe_value(None)
      }
      let mut best = values[0]
      for i = 1; i < values.length(); i = i + 1 {
        let order = sdk_compare(values[i], best, 0)
        if (suffix == "maximum" && !(order is @sdk.LT)) ||
          (suffix == "minimum" && !(order is @sdk.GT)) {
          best = values[i]
        }
      }
      sdk_maybe_value(Some(best))
    }
    "sum" | "product" => {
      let values = @sdk_list.to_array(sdk_value_list(args[0]))
      let has_float = values.any(fn(value) {
        value is @scheme.Number(@scheme.Number::Real(_))
      })
      if has_float {
        let floats = @sdk_list.from_array(
          values.map(fn(value) raise {
            match value {
              @scheme.Number(@scheme.Number::Real(number)) => number
              _ => raise @scheme.Invalid("Expected homogeneous List Float")
            }
          }),
        )
        @scheme.Number(
          @scheme.Number::Real(
            if suffix == "sum" {
              @sdk_list.sum_float(floats)
            } else {
              @sdk_list.product_float(floats)
            },
          ),
        )
      } else {
        let integers = @sdk_list.from_array(values.map(sdk_integer))
        exact_integer(
          if suffix == "sum" {
            @sdk_list.sum(integers)
          } else {
            @sdk_list.product(integers)
          },
        )
      }
    }
    "append" =>
      sdk_list_value(
        @sdk_list.append(sdk_value_list(args[0]), sdk_value_list(args[1])),
      )
    "concat" =>
      sdk_list_value(
        @sdk_list.concat(
          @sdk_list.from_array(
            @sdk_list.to_array(sdk_value_list(args[0])).map(sdk_value_list),
          ),
        ),
      )
    "concat-map" =>
      sdk_list_value(
        @sdk_list.concat_map(
          fn(value) raise { sdk_value_list(sdk_apply(rt, args[0], [value])) },
          sdk_value_list(args[1]),
        ),
      )
    "intersperse" =>
      sdk_list_value(@sdk_list.intersperse(args[0], sdk_value_list(args[1])))
    "is-empty" => @scheme.Boolean(@sdk_list.is_empty(sdk_value_list(args[0])))
    "head" => sdk_maybe_value(@sdk_list.head(sdk_value_list(args[0])))
    "tail" =>
      sdk_maybe_value(
        @sdk_list.tail(sdk_value_list(args[0])).map(sdk_list_value),
      )
    "take" =>
      sdk_list_value(@sdk_list.take(sdk_int(args[0]), sdk_value_list(args[1])))
    "drop" =>
      sdk_list_value(@sdk_list.drop(sdk_int(args[0]), sdk_value_list(args[1])))
    "partition" => {
      let (yes, no) = @sdk_list.partition(
        fn(value) raise { sdk_bool(sdk_apply(rt, args[0], [value])) },
        sdk_value_list(args[1]),
      )
      @scheme.Vector([sdk_list_value(yes), sdk_list_value(no)])
    }
    "unzip" => {
      let pairs = @sdk_list.from_array(
        @sdk_list.to_array(sdk_value_list(args[0])).map(sdk_list_pair),
      )
      let (left, right) = @sdk_list.unzip(pairs)
      @scheme.Vector([sdk_list_value(left), sdk_list_value(right)])
    }
    "sort" =>
      sdk_list_value(
        @sdk_list.sort_with(
          fn(a, b) raise { sdk_compare(a, b, 0) },
          sdk_value_list(args[0]),
        ),
      )
    "sort-by" =>
      sdk_list_value(
        @sdk_list.sort_with(
          fn(a, b) raise {
            sdk_compare(
              sdk_apply(rt, args[0], [a]),
              sdk_apply(rt, args[0], [b]),
              0,
            )
          },
          sdk_value_list(args[1]),
        ),
      )
    "sort-with" =>
      sdk_list_value(
        @sdk_list.sort_with(
          fn(a, b) raise { sdk_order(sdk_apply(rt, args[0], [a, b])) },
          sdk_value_list(args[1]),
        ),
      )
    "map2" =>
      sdk_list_value(
        @sdk_list.map2(
          fn(a, b) raise { sdk_apply(rt, args[0], [a, b]) },
          sdk_value_list(args[1]),
          sdk_value_list(args[2]),
        ),
      )
    "map3" =>
      sdk_list_value(
        @sdk_list.map3(
          fn(a, b, c) raise { sdk_apply(rt, args[0], [a, b, c]) },
          sdk_value_list(args[1]),
          sdk_value_list(args[2]),
          sdk_value_list(args[3]),
        ),
      )
    "map4" =>
      sdk_list_value(
        @sdk_list.map4(
          fn(a, b, c, d) raise { sdk_apply(rt, args[0], [a, b, c, d]) },
          sdk_value_list(args[1]),
          sdk_value_list(args[2]),
          sdk_value_list(args[3]),
          sdk_value_list(args[4]),
        ),
      )
    "map5" =>
      sdk_list_value(
        @sdk_list.map5(
          fn(a, b, c, d, e) raise { sdk_apply(rt, args[0], [a, b, c, d, e]) },
          sdk_value_list(args[1]),
          sdk_value_list(args[2]),
          sdk_value_list(args[3]),
          sdk_value_list(args[4]),
          sdk_value_list(args[5]),
        ),
      )
    "inner-join" =>
      sdk_list_value(
        @sdk_list.map(
          fn(pair) {
            let (a, b) = pair
            @scheme.Vector([a, b])
          },
          @sdk_list.inner_join(
            sdk_value_list(args[0]),
            fn(a, b) raise { sdk_bool(sdk_apply(rt, args[1], [a, b])) },
            sdk_value_list(args[2]),
          ),
        ),
      )
    "left-join" =>
      sdk_list_value(
        @sdk_list.map(
          fn(pair) {
            let (a, b) = pair
            @scheme.Vector([a, sdk_maybe_value(b)])
          },
          @sdk_list.left_join(
            sdk_value_list(args[0]),
            fn(a, b) raise { sdk_bool(sdk_apply(rt, args[1], [a, b])) },
            sdk_value_list(args[2]),
          ),
        ),
      )
    _ => raise @scheme.Unbound(name)
  }
}
