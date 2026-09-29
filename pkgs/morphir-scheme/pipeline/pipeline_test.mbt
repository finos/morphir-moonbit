///|
test "Scheme frontend through real Morphir IR and Scheme backend" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let reread = @ir_json.read(@ir_json.write(file))
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(reread, @ir.FQName::parse("user:main#main"), []),
    ),
    "42",
  )
  for
    source in [
      "(let ((x 10)) (let ((x 20) (y x)) (+ x y)))", "(letrec ((sum (lambda (n) (if (= n 0) 0 (+ n (sum (- n 1))))))) (sum 10))",
    ] {
    let ir = @frontend.compile_expression(source)
    assert_eq(
      @scheme.value_to_string(@backend.evaluate(ir)),
      @scheme.value_to_string(@scheme.eval_program(source)),
    )
  }
}

///|
test "scripted bottom-up IR transform retains source metadata" {
  let runtime = @pipeline.new_runtime()
  let result = runtime.eval(
    "(ir-eval (ir-rewrite (scheme->ir \"(+ 20 20)\") (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 1)) node))))",
  )
  assert_eq(@scheme.value_to_string(result), "42")
  let file = @frontend.compile_file("40")
  let transformed = @pipeline.transform_file(
    file, "(lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 2)) node))))",
  )
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(transformed, @ir.FQName::parse("user:main#main"), []),
    ),
    "42",
  )
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file(file, @ir.FQName::parse("user:main#main"), []),
    ),
    "40",
  )
}

///|
test "ir-eval uses host native bindings in the caller's runtime" {
  let runtime = @pipeline.new_runtime()
  let name = @ir.FQName::parse("test:main#answer")
  @backend.register_accelerator(runtime, name, 0, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  runtime.set_global(
    "input",
    @scheme.IR(@ir.Value::Reference(@ir.ValueAttributes::default(), name)),
  )
  assert_eq(@scheme.value_to_string(runtime.eval("(ir-eval input)")), "42")
}

///|
test "lowering preserves shadowed parameters and sequential bindings" {
  for
    source in [
      "(let ((f (lambda (x) (lambda (x) x)))) ((f 1) 42))", "(let* ((x 20) (x (+ x 22))) x)",
      "(let ((x 1.0)) x)",
    ] {
    assert_eq(
      @scheme.value_to_string(
        @backend.evaluate(@frontend.compile_expression(source)),
      ),
      @scheme.value_to_string(@scheme.eval_program(source)),
    ) catch {
      @scheme.Unsupported(message) => fail(source + ": " + message)
      error => raise error
    }
  }
  for source in ["1 (define x 2)", "(set! x 2)", "1/2"] {
    let refused = try {
      ignore(@frontend.compile_file(source))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
test "rewriting preserves explicit attributes" {
  let attributes : @ir.ValueAttributes = {
    source: Some({ start_line: 2, start_column: 3, end_line: 2, end_column: 5, }),
    inferred_type: Some(@frontend.unknown_type()),
    extensions: Map([]),
  }
  let value = @ir.Value::Literal(attributes, @ir.Literal::IntegerLiteral("40"))
  let runtime = @pipeline.new_runtime()
  runtime.set_global("input", @scheme.IR(value))
  let result = runtime.eval("(ir-with-integer input 42)").as_ir()
  assert_eq(
    result,
    @ir.Value::Literal(attributes, @ir.Literal::IntegerLiteral("42")),
  )
  assert_eq(runtime.lookup("input").as_ir(), value)
}
