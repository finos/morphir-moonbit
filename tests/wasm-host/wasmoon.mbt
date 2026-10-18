///|
async fn main {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let bytes = @fs.read_file(@env.args()[1]).binary()
  let instance = runtime.instantiate("moonbit-rich-probe", bytes)
  let exchange = instance.bind("exchange")
  let calls = instance.bind("calls")
  let packet : @component.ComponentValue = Record([
    ("label", String("Morphir 😀 𝄞 e\u0301 雪\u0000")),
    ("payload", List([U8(224), U8(1), U8(0), U8(234), U8(33), U8(42)])),
    ("encoding", Enum("ion-binary")),
  ])
  assert_eq(calls.call([]), [U32(0U)])
  let first = exchange.call([packet])
  assert_eq(first, [ResultOk(Some(packet))])
  for _ in 0..<100 {
    assert_eq(exchange.call([packet]), first)
  }
  assert_eq(first, [ResultOk(Some(packet))])
  assert_eq(calls.call([]), [U32(101U)])
  let wrong_type = try {
    exchange.call([U32(1U)]) |> ignore
    false
  } catch {
    TypeMismatch(..) => true
    _ => false
  }
  assert_true(wrong_type)
  assert_eq(calls.call([]), [U32(101U)])
  instance.bind("close").call([]) |> ignore
  assert_eq(exchange.call([packet]), [ResultErr(Some(Variant("closed", None)))])
  let fresh = runtime.instantiate("moonbit-fresh-probe", bytes)
  assert_eq(fresh.bind("calls").call([]), [U32(0U)])
  let spin = fresh.bind("spin")
  let bounded = try {
    runtime.with_execution_limits(safepoints=Some(5000L), fn() raise {
      spin.call([]) |> ignore
    })
    false
  } catch {
    @component.ComponentRuntimeError::ExecutionBudgetExceeded => true
    _ => false
  }
  assert_true(bounded)
  runtime.close()
  runtime.close()
  let closed = try {
    calls.call([]) |> ignore
    false
  } catch {
    RuntimeClosed => true
    _ => false
  }
  assert_true(closed)
  println(
    "{\"host\":\"wasmoon-native-interpreter\",\"unicode\":true,\"ionBytes\":true,\"acceptedCalls\":101,\"typeRefusal\":true,\"closedResult\":true,\"freshInstance\":true,\"executionBudget\":true,\"runtimeClosed\":true}",
  )
}
