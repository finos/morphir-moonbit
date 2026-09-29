///|
fn sdk_error(name : String, error : @sdk.SdkError) -> @scheme.SchemeError {
  let detail = match error {
    @sdk.DivisionByZero => "division by zero"
    @sdk.InvalidNumber(message) => "invalid number: " + message
    @sdk.OutOfRange(message) => "out of range: " + message
    @sdk.InvalidComparison(message) => "invalid comparison: " + message
    @sdk.UnrepresentableText(message) => "unrepresentable text: " + message
  }
  @scheme.Invalid(name + ": " + detail)
}

///|
fn exact_integer(value : @integer.Integer) -> @scheme.Value {
  @scheme.Number(@scheme.Number::Integer(@integer.to_bigint(value)))
}

///|
fn sdk_integer_binary(
  name : String,
  left : @integer.Integer,
  right : @integer.Integer,
) -> @integer.Integer raise @sdk.SdkError {
  match name {
    "morphir/SDK:basics#add" => @basics.add_int(left, right)
    "morphir/SDK:basics#subtract" => @basics.subtract_int(left, right)
    "morphir/SDK:basics#multiply" => @basics.multiply_int(left, right)
    "morphir/SDK:basics#integer-divide" => @basics.integer_divide(left, right)
    "morphir/SDK:basics#mod-by" => @basics.mod_by(left, right)
    "morphir/SDK:basics#remainder-by" => @basics.remainder_by(left, right)
    "morphir/SDK:basics#power" => @basics.power_int(left, right)
    _ => raise @sdk.InvalidNumber("Unsupported integer SDK operation")
  }
}

///|
fn install_sdk(runtime : @scheme.Runtime) -> Unit {
  runtime.define_native("%morphir-sdk", fn(_rt, args) raise {
    if args.length() == 2 {
      return sdk_unary(args[0].as_text(), args[1])
    }
    @scheme.arity(args, 3, "Morphir SDK")
    let name = args[0].as_text()
    let left = args[1]
    let right = args[2]
    match (left, right) {
      (@scheme.Value::Text(a), @scheme.Value::Text(b)) => {
        if name != "morphir/SDK:string#append" {
          raise @scheme.Invalid(name + ": unsupported Text SDK operation")
        }
        let result = @sdk_string.append(
          @sdk.Text::from_string(a),
          @sdk.Text::from_string(b),
        )
        @scheme.Value::Text(
          result.to_string() catch {
            error => raise sdk_error(name, error)
          },
        )
      }
      (
        @scheme.Number(@scheme.Number::Integer(a)),
        @scheme.Number(@scheme.Number::Integer(b)),
      ) => {
        if name == "morphir/SDK:basics#divide" {
          raise @scheme.Invalid(name + ": expected Float operands")
        }
        let result = sdk_integer_binary(
          name,
          @integer.from_bigint(a),
          @integer.from_bigint(b),
        ) catch {
          error => raise sdk_error(name, error)
        }
        exact_integer(result)
      }
      (
        @scheme.Number(@scheme.Number::Real(a)),
        @scheme.Number(@scheme.Number::Real(b)),
      ) => {
        let result = match name {
          "morphir/SDK:basics#add" => @basics.add_float(a, b)
          "morphir/SDK:basics#subtract" => @basics.subtract_float(a, b)
          "morphir/SDK:basics#multiply" => @basics.multiply_float(a, b)
          "morphir/SDK:basics#divide" => @basics.divide(a, b)
          "morphir/SDK:basics#power" => @basics.power_float(a, b)
          _ => raise @scheme.Invalid(name + ": expected Integer operands")
        }
        @scheme.Number(@scheme.Number::Real(result))
      }
      _ => raise @scheme.Invalid(name + ": incompatible SDK operands")
    }
  })
}

///|
fn sdk_unary(name : String, input : @scheme.Value) -> @scheme.Value raise {
  match input {
    @scheme.Number(@scheme.Number::Integer(n)) => {
      let integer = @integer.from_bigint(n)
      let result = match name {
        "morphir/SDK:basics#negate" =>
          exact_integer(@basics.negate_int(integer))
        "morphir/SDK:basics#abs" => exact_integer(@basics.abs_int(integer))
        "morphir/SDK:basics#to-float" =>
          @scheme.Number(@scheme.Number::Real(@basics.to_float(integer)))
        _ => raise @scheme.Invalid(name + ": unsupported Integer SDK operation")
      }
      result
    }
    @scheme.Number(@scheme.Number::Real(value)) => {
      let result = match name {
        "morphir/SDK:basics#negate" =>
          @scheme.Value::Number(
            @scheme.Number::Real(@basics.negate_float(value)),
          )
        "morphir/SDK:basics#abs" =>
          @scheme.Value::Number(@scheme.Number::Real(@basics.abs_float(value)))
        "morphir/SDK:basics#round" =>
          exact_integer(
            @basics.round(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#floor" =>
          exact_integer(
            @basics.floor(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#ceiling" =>
          exact_integer(
            @basics.ceiling(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#truncate" =>
          exact_integer(
            @basics.truncate(value) catch {
              error => raise sdk_error(name, error)
            },
          )
        "morphir/SDK:basics#is-na-n" => @scheme.Boolean(@basics.is_nan(value))
        "morphir/SDK:basics#is-infinite" =>
          @scheme.Boolean(@basics.is_infinite(value))
        _ => raise @scheme.Invalid(name + ": unsupported Float SDK operation")
      }
      result
    }
    _ => raise @scheme.Invalid(name + ": incompatible SDK operand")
  }
}
