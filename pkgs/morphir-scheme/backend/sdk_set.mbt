///|
fn sdk_key_compare(
  a : @scheme.Value,
  b : @scheme.Value,
) -> @sdk.Order raise @sdk.SdkError {
  sdk_compare(a, b, 0) catch {
    _ => raise @sdk.InvalidComparison("Expected comparable Morphir key")
  }
}

///|
fn sdk_set(value : @scheme.Value) -> @sdk_set.Set[@scheme.Value] raise {
  match value {
    @scheme.Tagged("sdk-set", [items]) =>
      @sdk_set.from_list(sdk_key_compare, sdk_value_list(items))
    _ => raise @scheme.Invalid("Expected Morphir Set")
  }
}

///|
fn sdk_set_value(value : @sdk_set.Set[@scheme.Value]) -> @scheme.Value {
  @scheme.Tagged("sdk-set", [sdk_list_value(@sdk_set.to_list(value))])
}

///|
fn sdk_set_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name.clamped_view(start="morphir/SDK:set#".length()).to_owned()
  match suffix {
    "empty" => sdk_set_value(@sdk_set.empty(sdk_key_compare))
    "singleton" => sdk_set_value(@sdk_set.singleton(sdk_key_compare, args[0]))
    "insert" => sdk_set_value(@sdk_set.insert(args[0], sdk_set(args[1])))
    "remove" => sdk_set_value(@sdk_set.remove(args[0], sdk_set(args[1])))
    "is-empty" => @scheme.Boolean(@sdk_set.is_empty(sdk_set(args[0])))
    "member" => @scheme.Boolean(@sdk_set.member(args[0], sdk_set(args[1])))
    "size" => exact_integer(@integer.from_int(@sdk_set.size(sdk_set(args[0]))))
    "to-list" => sdk_list_value(@sdk_set.to_list(sdk_set(args[0])))
    "from-list" =>
      sdk_set_value(
        @sdk_set.from_list(sdk_key_compare, sdk_value_list(args[0])),
      )
    "union" => sdk_set_value(@sdk_set.union(sdk_set(args[0]), sdk_set(args[1])))
    "intersect" =>
      sdk_set_value(@sdk_set.intersect(sdk_set(args[0]), sdk_set(args[1])))
    "diff" => sdk_set_value(@sdk_set.diff(sdk_set(args[0]), sdk_set(args[1])))
    "map" => {
      let values = @sdk_list.to_array(@sdk_set.to_list(sdk_set(args[1])))
      let transformed = values.map(fn(value) raise {
        sdk_apply(rt, args[0], [value])
      })
      sdk_set_value(
        @sdk_set.from_list(sdk_key_compare, @sdk_list.from_array(transformed)),
      )
    }
    "foldl" | "foldr" => {
      let values = @sdk_list.to_array(@sdk_set.to_list(sdk_set(args[2])))
      let mut acc = args[1]
      if suffix == "foldl" {
        for value in values {
          acc = sdk_apply(rt, args[0], [value, acc])
        }
      } else {
        for i = values.length() - 1; i >= 0; i = i - 1 {
          acc = sdk_apply(rt, args[0], [values[i], acc])
        }
      }
      acc
    }
    "filter" | "partition" => {
      let values = @sdk_list.to_array(@sdk_set.to_list(sdk_set(args[1])))
      let yes = []
      let no = []
      for value in values {
        if sdk_bool(sdk_apply(rt, args[0], [value])) {
          yes.push(value)
        } else {
          no.push(value)
        }
      }
      let accepted = sdk_set_value(
        @sdk_set.from_list(sdk_key_compare, @sdk_list.from_array(yes)),
      )
      if suffix == "filter" {
        accepted
      } else {
        let rejected = sdk_set_value(
          @sdk_set.from_list(sdk_key_compare, @sdk_list.from_array(no)),
        )
        @scheme.Vector([accepted, rejected])
      }
    }
    _ => raise @scheme.Unbound(name)
  }
}
