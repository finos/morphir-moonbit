///|
pub(all) struct InvocationEntry {
  fqname : String
  generated_name : String
  inputs : Array[@execution.ValueType]
  output : @execution.ValueType
}

///|
fn boundary_type(t : Lowered) -> @execution.ValueType? {
  match t {
    Atom(Integer) => Some(@execution.Int)
    Atom(Boolean) => Some(@execution.Bool)
    Atom(Unit) => Some(@execution.Unit)
    _ => None
  }
}

///|
fn invocation_entry(d : Declaration) -> InvocationEntry? {
  if !d.public {
    return None
  }
  let inputs = []
  for (_, t) in d.inputs {
    guard boundary_type(t) is Some(v) else { return None }
    inputs.push(v)
  }
  guard boundary_type(d.output) is Some(output) else { return None }
  Some({
    fqname: d.fqname.to_canonical(),
    generated_name: "v_" + hex(d.fqname.to_canonical()),
    inputs,
    output,
  })
}

///|
/// A separate consumer package. Only entry selection affects its source.
pub fn invocation_driver(
  output : Output,
  entries : Array[String],
) -> Array[Artifact] raise GenerationError {
  let names = entries.copy()
  names.sort()
  let cases = []
  let seen = Map([])
  for name in names {
    if seen.contains(name) {
      continue
    }
    seen[name] = true
    guard output.invocations.filter(e => e.fqname == name).get(0) is Some(entry) else {
      raise Invalid(
        "moonbit.unsupported_entry", name, "A public Int/Bool/Unit entry is required",
      )
    }
    let arguments = []
    for i = 0; i < entry.inputs.length(); i = i + 1 {
      arguments.push(
        match entry.inputs[i] {
          Int =>
            "@integer.from_bigint(int_arg(call.arguments[" +
            i.to_string() +
            "]))"
          Bool => "bool_arg(call.arguments[" + i.to_string() + "])"
          Unit => "unit_arg(call.arguments[" + i.to_string() + "])"
        },
      )
    }
    let mut call = "@model." + entry.generated_name + "()"
    for argument in arguments {
      call = "{ let function = " + call + "; function(" + argument + ") }"
    }
    let wrapped = match entry.output {
      Int => "@execution.Integer(@integer.to_bigint(" + call + "))"
      Bool => "@execution.Boolean(" + call + ")"
      Unit => "{ " + call + "; @execution.Unit }"
    }
    cases.push(
      quote(name) +
      " => { if call.arguments.length() != " +
      entry.inputs.length().to_string() +
      " { raise @execution.Invalid(\"execution.wrong_arity\") }; " +
      wrapped +
      " }",
    )
  }
  let source =
    #|///|
    #|fn int_arg(v : @execution.Value) -> @bigint.BigInt raise { match v { Integer(n) => n; _ => raise @execution.Invalid("execution.wrong_type") } }
    #|///|
    #|fn bool_arg(v : @execution.Value) -> Bool raise { match v { Boolean(b) => b; _ => raise @execution.Invalid("execution.wrong_type") } }
    #|///|
    #|fn unit_arg(v : @execution.Value) -> Unit raise { match v { Unit => (); _ => raise @execution.Invalid("execution.wrong_type") } }
    #|///|
    #|pub fn invoke(call : @execution.Call) -> @execution.Value raise {
    #|  match call.entry {
    #|
  let ending =
    #|    _ => raise @execution.Invalid("execution.unknown_entry")
    #|  }
    #|}
    #|
  [
    {
      path: "moon.mod",
      role: ModuleManifest,
      content: Text(
        "name = \"morphir-generated/driver\"\nversion = \"0.0.0\"\nimport {\n" +
        quote(output.project.module_name + "@0.0.0") +
        ",\n\"finos/morphir-sdk@0.1.0\",\n\"finos/morphir-execution@0.1.0\",\n\"moonrockz/ion@0.3.0\",\n}\n",
      ),
    },
    {
      path: "moon.pkg",
      role: PackageManifest,
      content: Text(
        "import {\n" +
        quote(output.project.module_name) +
        " @model,\n\"finos/morphir-sdk/integer\",\n\"finos/morphir-execution\" @execution,\n\"moonbitlang/core/bigint\",\n}\nwarnings = \"-16-29\"\n",
      ),
    },
    {
      path: "driver.mbt",
      role: Source,
      content: Text(source + cases.join("\n") + "\n" + ending),
    },
  ]
}
