///|
pub(all) struct Plan {
  unit : @data.IRUnit
  suite : @protocol.Suite
  library : @moonbit.Output
  driver : Array[@moonbit.Artifact]
  target : String
}

///|
/// Providers own executable storage; the engine never assumes a filesystem.
pub(all) struct InvocationResults {
  values : Array[@protocol.Value]
  evidence : Json
}

///|
pub(all) struct Session {
  id : String
  build : (Plan) -> Json raise
  invoke : (@protocol.Suite) -> InvocationResults raise
  dispose : () -> Unit raise
}

///|
pub(all) struct Provider {
  targets : Array[String]
  acquire : () -> Session raise
}

///|
pub(all) struct Evaluator {
  profile : String
  evaluate : (@data.IRUnit, @protocol.Call) -> @protocol.Value raise
}

///|
pub(all) struct CallResult {
  id : String
  actual : @protocol.Value
  expected : @protocol.Value?
  matches : Bool
}

///|
pub(all) struct Report {
  calls : Array[CallResult]
  evidence : Json
  invocation_evidence : Json
  evaluator : String?
  target : String
}

///|
pub fn Report::successful(self : Report) -> Bool {
  !self.calls.is_empty() && self.calls.all(c => c.matches)
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "profile": "morphir-execution-v1",
    "successful": self.successful(),
    "target": self.target,
    "evaluator": match self.evaluator {
      Some(s) => Json::string(s)
      None => Json::null()
    },
    "evidence": self.evidence,
    "invocationEvidence": self.invocation_evidence,
    "calls": self.calls.map(c => {
      (
        {
          "id": c.id,
          "actual": c.actual.to_json(),
          "expected": match c.expected {
            Some(v) => v.to_json()
            None => Json::null()
          },
          "matches": c.matches,
        } : Json)
    }),
  }
}

///|
/// Validation and pure generation occur before acquiring a provider session.
pub fn plan(
  unit : @data.IRUnit,
  suite : @protocol.Suite,
  target? : String = "js",
) -> Plan raise {
  suite.validate()
  if target != "js" {
    raise @protocol.Invalid("execution.unsupported_target: " + target)
  }
  let library = @moonbit.generate({
    unit_id: unit.id,
    ir: unit.distribution,
    metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: unit.annotations,
    provenance: unit.provenance,
  })
  validate_calls(library, suite)
  {
    unit,
    suite,
    library,
    driver: @moonbit.invocation_driver(library, suite.calls.map(c => c.entry)),
    target,
  }
}

///|
fn validate_calls(
  library : @moonbit.Output,
  suite : @protocol.Suite,
) -> Unit raise {
  for call in suite.calls {
    guard library.invocations.filter(e => e.fqname == call.entry).get(0)
      is Some(entry) else {
      raise @protocol.Invalid(
        "execution.entry_not_public_or_supported: " + call.entry,
      )
    }
    if call.arguments.length() != entry.inputs.length() {
      raise @protocol.Invalid("execution.wrong_arity: " + call.id)
    }
    for i = 0; i < call.arguments.length(); i = i + 1 {
      if call.arguments[i].value_type() != entry.inputs[i] {
        raise @protocol.Invalid("execution.wrong_type: " + call.id)
      }
    }
  }
}

///|
pub fn Evaluator::scheme() -> Evaluator {
  {
    profile: "scheme-portable-v1/shared-sdk/bounded",
    evaluate: fn(unit, call) raise {
      let runtime = @scheme.Runtime::new(limits={
        steps: 1000000,
        depth: 128,
        frames: 100000,
      })
      @backend.install(runtime, accelerators=false)
      let result = @backend.run_file_in(
        runtime,
        unit.distribution,
        @ir.FQName::parse(call.entry),
        call.arguments.map(v => {
          match v {
            Integer(n) => @scheme.integer(n.to_string())
            Boolean(b) => @scheme.Boolean(b)
            Unit => @scheme.Unit
          }
        }),
      )
      match result {
        Number(Integer(n)) => @protocol.Integer(n)
        Boolean(b) => @protocol.Boolean(b)
        Unit => @protocol.Unit
        _ => raise @protocol.Invalid("execution.evaluator_type")
      }
    },
  }
}

///|
pub fn run(
  plan : Plan,
  provider : Provider,
  evaluator? : Evaluator? = None,
  observer? : @observe.Observer = @observe.Observer::noop(),
  cancelled? : () -> Bool = fn() { false },
) -> Report raise {
  if !provider.targets.contains(plan.target) {
    raise @protocol.Invalid("execution.provider_target")
  }
  // Revalidate mutable caller-owned arrays before any external capability.
  let frozen = @protocol.Suite::decode(
    plan.suite.encode("ion-binary"),
    "ion-binary",
  )
  validate_calls(plan.library, frozen)
  fn check() -> Unit raise {
    if cancelled() {
      raise @protocol.Invalid("Cancelled")
    }
  }
  observer
  .scope()
  .observe(@observe.Execute, fn(scope) raise {
    check()
    let session = (provider.acquire)()
    let mut report : Report? = None
    let mut failure : Error? = None
    try {
      if session.id == "" {
        raise @protocol.Invalid("execution.invalid_lease")
      }
      let evidence = scope.observe(@observe.Build, fn(_) raise {
        check()
        (session.build)(plan)
      })
      let invocation = scope.observe(@observe.Invoke, fn(_) raise {
        check()
        (session.invoke)(frozen)
      })
      let actual = invocation.values
      if actual.length() != frozen.calls.length() {
        raise @protocol.Invalid("execution.result_count")
      }
      let results = []
      for i = 0; i < frozen.calls.length(); i = i + 1 {
        check()
        let call = frozen.calls[i]
        let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
        if actual[i].value_type() != entry.output {
          raise @protocol.Invalid("execution.result_type")
        }
        let expected = match evaluator {
          Some(e) =>
            Some(
              scope.observe(@observe.Evaluate, fn(_) raise {
                (e.evaluate)(plan.unit, call)
              }),
            )
          None => None
        }
        let matches = scope.observe(@observe.Compare, fn(_) {
          match expected {
            Some(value) => value == actual[i]
            None => true
          }
        })
        results.push({ id: call.id, actual: actual[i], expected, matches, })
      }
      report = Some({
        calls: results,
        evidence,
        invocation_evidence: invocation.evidence,
        evaluator: evaluator.map(e => e.profile),
        target: plan.target,
      })
    } catch {
      error => failure = Some(error)
    }
    scope.observe(@observe.Cleanup, fn(_) raise { (session.dispose)() }) catch {
      error =>
        raise @protocol.Invalid(
          "execution.cleanup_failed: " +
          failure.map(e => e.to_string()).unwrap_or("") +
          " " +
          error.to_string(),
        )
    }
    if failure is Some(error) {
      raise error
    }
    check()
    report.unwrap()
  })
}
