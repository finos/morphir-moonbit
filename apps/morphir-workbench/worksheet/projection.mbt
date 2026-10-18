///|
fn project_value(
  value : @scheme.Value,
  depth : Int32,
) -> @execution.Value raise {
  if depth > 64 {
    raise @execution.Invalid("execution.value_limit")
  }
  fn child(value : @scheme.Value) -> @execution.Value raise {
    project_value(value, depth + 1)
  }
  match value {
    Number(Integer(number)) => @execution.Integer(number)
    Number(Real(number)) => @execution.Float64(number.reinterpret_as_uint64())
    Boolean(value) => @execution.Boolean(value)
    Text(text) =>
      @execution.Text(text.code_units().to_owned().map(unit => unit.to_int()))
    Character(character) =>
      @execution.Character(
        character.to_string().code_units().to_owned().map(unit => unit.to_int()),
      )
    Unit => @execution.Unit
    Nil => @execution.Sequence([])
    Pair(_, _) => {
      let items : Array[@execution.Value] = []
      let mut rest = value
      while rest is @scheme.Pair(head, tail) {
        if items.length() >= 100000 {
          raise @execution.Invalid("execution.value_limit")
        }
        items.push(child(head))
        rest = tail
      }
      if !(rest is @scheme.Nil) {
        raise @execution.Invalid("worksheet.value_unsupported")
      }
      @execution.Sequence(items)
    }
    Vector(items) => @execution.Product(items.map(child))
    Record(fields) => {
      let names = fields.keys().collect()
      names.sort()
      @execution.Record(names.map(name => (name, child(fields[name]))))
    }
    _ => raise @execution.Invalid("worksheet.value_unsupported")
  }
}
