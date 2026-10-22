///|
fn fault_command() -> @argparse.Command {
  @argparse.Command(
    // Keep dash-leading filenames and historically ignored trailing operands.
    "protocol-fault",
    disable_help_flag=true,
    positionals=[
      @argparse.PositionArg(
        "checkpoint",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "fault",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "ignored",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
  )
}

///|
/// Acceptance-only mutator uses the pipeline's Ion codec, including symbol tables.
fn main raise {
  // The library removes the runtime prefix on both native and Node hosts.
  let args = fault_command().parse() catch {
    // Missing operands historically panic without writing to either channel.
    _ => panic()
  }
  let path = args.values["checkpoint"][0]
  let fault = args.values["fault"][0]
  let bytes = @fs.read_file_to_bytes(path)
  if fault == "truncated" {
    @fs.write_bytes_to_file(path, bytes[:bytes.length() - 1].to_owned())
    return
  }
  if fault == "malformed" {
    @fs.write_bytes_to_file(path, b"not Ion")
    return
  }
  if fault == "oversize" {
    @fs.write_bytes_to_file(path, Bytes::make(1048577, 0))
    return
  }
  let fields = @protocol.fields(@binary.read_binary_value(bytes[:]), [
    "profile", "suite_identity", "calls", "traceparent", "extensions",
  ])
  guard @protocol.required(fields, "calls").kind() is List(calls) else {
    abort("calls")
  }
  let calls = calls.copy()
  match fault {
    "missing" => {
      ignore(calls.pop())
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "extra" => {
      calls.push(calls[0])
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "duplicate" => {
      calls[1] = calls[0]
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "reordered" => {
      let first = calls[0]
      calls[0] = calls[1]
      calls[1] = first
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "wrong-id" | "duration" | "value" => {
      let call = @protocol.fields(calls[0], ["id", "value", "duration_seconds"])
      match fault {
        "wrong-id" => call["id"] = @ion.IonValue::string("unknown")
        "duration" => call["duration_seconds"] = @ion.IonValue::float(-1.0)
        _ => call["value"] = @ion.IonValue::string("wrong type")
      }
      calls[0] = @protocol.record([
        ("id", call["id"]),
        ("value", call["value"]),
        ("duration_seconds", call["duration_seconds"]),
      ])
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "wrong-suite" =>
      fields["suite_identity"] = @ion.IonValue::string("0".repeat(64))
    "wrong-profile" =>
      fields["profile"] = @ion.IonValue::string("morphir-outcomes-v0")
    "wrong-trace" => fields["traceparent"] = @ion.IonValue::string("unrelated")
    "extensions" => fields["extensions"] = @ion.IonValue::string("changed")
    "duplicate-field" => ()
    _ => abort("unknown fault")
  }
  let output = [
    "profile", "suite_identity", "calls", "traceparent", "extensions",
  ].map(name => (name, fields[name]))
  if fault == "duplicate-field" {
    output.push(("calls", fields["calls"]))
  }
  @fs.write_bytes_to_file(
    path,
    @binary.write_binary_value(@protocol.record(output)),
  )
}
