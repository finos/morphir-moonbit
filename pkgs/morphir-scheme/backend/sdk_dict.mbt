///|
fn sdk_dict(
  value : @scheme.Value,
) -> @sdk_dict.Dict[@scheme.Value, @scheme.Value] raise {
  match value {
    @scheme.Tagged("sdk-dict", [items]) => {
      let pairs = sdk_value_list(items)
      let entries = @sdk_list.map(sdk_list_pair, pairs)
      @sdk_dict.from_list(sdk_key_compare, entries)
    }
    _ => raise @scheme.Invalid("Expected Morphir Dict")
  }
}

///|
fn sdk_dict_value(
  value : @sdk_dict.Dict[@scheme.Value, @scheme.Value],
) -> @scheme.Value {
  let pairs = @sdk_list.map(
    fn(pair) {
      let (key, item) = pair
      @scheme.Value::Vector([key, item])
    },
    @sdk_dict.to_list(value),
  )
  @scheme.Tagged("sdk-dict", [sdk_list_value(pairs)])
}

///|
fn sdk_dict_dispatch(
  rt : @scheme.Runtime,
  name : String,
  args : Array[@scheme.Value],
) -> @scheme.Value raise {
  let suffix = name.clamped_view(start="morphir/SDK:dict#".length()).to_owned()
  match suffix {
    "empty" => sdk_dict_value(@sdk_dict.empty(sdk_key_compare))
    "singleton" =>
      sdk_dict_value(@sdk_dict.singleton(sdk_key_compare, args[0], args[1]))
    "insert" =>
      sdk_dict_value(@sdk_dict.insert(args[0], args[1], sdk_dict(args[2])))
    "remove" => sdk_dict_value(@sdk_dict.remove(args[0], sdk_dict(args[1])))
    "is-empty" => @scheme.Boolean(@sdk_dict.is_empty(sdk_dict(args[0])))
    "member" => @scheme.Boolean(@sdk_dict.member(args[0], sdk_dict(args[1])))
    "get" => sdk_maybe_value(@sdk_dict.get(args[0], sdk_dict(args[1])))
    "size" =>
      exact_integer(@integer.from_int(@sdk_dict.size(sdk_dict(args[0]))))
    "keys" => sdk_list_value(@sdk_dict.keys(sdk_dict(args[0])))
    "values" => sdk_list_value(@sdk_dict.values(sdk_dict(args[0])))
    "to-list" => {
      let entries = @sdk_list.map(
        fn(pair) {
          let (key, item) = pair
          @scheme.Value::Vector([key, item])
        },
        @sdk_dict.to_list(sdk_dict(args[0])),
      )
      sdk_list_value(entries)
    }
    "from-list" => {
      let pairs = @sdk_list.map(sdk_list_pair, sdk_value_list(args[0]))
      sdk_dict_value(@sdk_dict.from_list(sdk_key_compare, pairs))
    }
    "union" =>
      sdk_dict_value(@sdk_dict.union(sdk_dict(args[0]), sdk_dict(args[1])))
    "intersect" =>
      sdk_dict_value(@sdk_dict.intersect(sdk_dict(args[0]), sdk_dict(args[1])))
    "diff" =>
      sdk_dict_value(@sdk_dict.diff(sdk_dict(args[0]), sdk_dict(args[1])))
    "update" => {
      let original = sdk_dict(args[2])
      let previous = @sdk_dict.get(args[0], original)
      match sdk_maybe(sdk_apply(rt, args[1], [sdk_maybe_value(previous)])) {
        Some(value) =>
          sdk_dict_value(@sdk_dict.insert(args[0], value, original))
        None => sdk_dict_value(@sdk_dict.remove(args[0], original))
      }
    }
    "map" => {
      let entries = @sdk_list.to_array(@sdk_dict.to_list(sdk_dict(args[1])))
      let changed = entries.map(fn(pair) raise {
        let (key, value) = pair
        (key, sdk_apply(rt, args[0], [key, value]))
      })
      sdk_dict_value(
        @sdk_dict.from_list(sdk_key_compare, @sdk_list.from_array(changed)),
      )
    }
    "foldl" | "foldr" => {
      let entries = @sdk_list.to_array(@sdk_dict.to_list(sdk_dict(args[2])))
      let mut acc = args[1]
      if suffix == "foldl" {
        for pair in entries {
          let (key, value) = pair
          acc = sdk_apply(rt, args[0], [key, value, acc])
        }
      } else {
        for i = entries.length() - 1; i >= 0; i = i - 1 {
          let (key, value) = entries[i]
          acc = sdk_apply(rt, args[0], [key, value, acc])
        }
      }
      acc
    }
    "filter" | "partition" => {
      let entries = @sdk_list.to_array(@sdk_dict.to_list(sdk_dict(args[1])))
      let yes = []
      let no = []
      for pair in entries {
        let (key, value) = pair
        if sdk_bool(sdk_apply(rt, args[0], [key, value])) {
          yes.push(pair)
        } else {
          no.push(pair)
        }
      }
      let accepted = sdk_dict_value(
        @sdk_dict.from_list(sdk_key_compare, @sdk_list.from_array(yes)),
      )
      if suffix == "filter" {
        accepted
      } else {
        let rejected = sdk_dict_value(
          @sdk_dict.from_list(sdk_key_compare, @sdk_list.from_array(no)),
        )
        @scheme.Vector([accepted, rejected])
      }
    }
    "merge" => {
      let left = @sdk_list.to_array(@sdk_dict.to_list(sdk_dict(args[3])))
      let right = @sdk_list.to_array(@sdk_dict.to_list(sdk_dict(args[4])))
      let mut i = 0
      let mut j = 0
      let mut acc = args[5]
      while i < left.length() || j < right.length() {
        if i == left.length() {
          let (key, value) = right[j]
          acc = sdk_apply(rt, args[2], [key, value, acc])
          j += 1
        } else if j == right.length() {
          let (key, value) = left[i]
          acc = sdk_apply(rt, args[0], [key, value, acc])
          i += 1
        } else {
          let (left_key, left_value) = left[i]
          let (right_key, right_value) = right[j]
          match sdk_compare(left_key, right_key, 0) {
            @sdk.LT => {
              acc = sdk_apply(rt, args[0], [left_key, left_value, acc])
              i += 1
            }
            @sdk.EQ => {
              acc = sdk_apply(rt, args[1], [
                left_key, left_value, right_value, acc,
              ])
              i += 1
              j += 1
            }
            @sdk.GT => {
              acc = sdk_apply(rt, args[2], [right_key, right_value, acc])
              j += 1
            }
          }
        }
      }
      acc
    }
    _ => raise @scheme.Unbound(name)
  }
}
