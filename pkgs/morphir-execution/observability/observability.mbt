///|
pub(all) enum Stage {
  Plan
  Decode
  Generate
  Build
  Invoke
  Evaluate
  Compare
  Cleanup
  Execute
  Legacy
} derive(Eq, Debug)

///|
pub fn Stage::name(self : Stage) -> String {
  match self {
    Plan => "plan"
    Decode => "decode"
    Generate => "generate"
    Build => "build"
    Invoke => "invoke"
    Evaluate => "evaluate"
    Compare => "compare"
    Cleanup => "cleanup"
    Execute => "execute"
    Legacy => "legacy"
  }
}

///|
pub(all) enum Signal {
  Started
  Succeeded
  Failed
  Cancelled
  Notice
} derive(Eq, Debug)

///|
pub(all) enum Delivery {
  Accepted
  Filtered
  Dropped
  Unavailable
} derive(Eq, Debug)

///|
pub(all) struct ObservationContext {
  run_id : String
  span_id : String
  parent_id : String
}

///|
/// Fixed fields exclude model values, paths, environment and unbounded labels.
pub(all) struct Observation {
  context : ObservationContext
  sequence : Int
  stage : Stage
  signal : Signal
  wall_seconds : Double
  duration_seconds : Double
}

///|
pub(all) struct Observer {
  enabled : () -> Bool
  try_record : (Observation) -> Delivery
  monotonic : () -> Double
  wall : () -> Double
  next_id : () -> String
  run_id : String
  sequence : Ref[Int]
}

///|
pub fn Observer::noop() -> Observer {
  {
    enabled: fn() { false },
    try_record: fn(_) { Filtered },
    monotonic: fn() { 0.0 },
    wall: fn() { 0.0 },
    next_id: fn() { "" },
    run_id: "",
    sequence: Ref(0),
  }
}

///|
pub struct Scope {
  priv observer : Observer
  priv context : ObservationContext
  priv sequence : Ref[Int]
}

///|
pub fn Observer::scope(self : Observer) -> Scope {
  {
    observer: self,
    context: { run_id: self.run_id, span_id: "", parent_id: "", },
    sequence: self.sequence,
  }
}

///|
/// Sinks cannot raise. Host adapters must contain I/O failures and report health separately.
pub fn[T] Scope::observe(
  self : Scope,
  stage : Stage,
  body : (Scope) -> T raise,
) -> T raise {
  let o = self.observer
  if !(o.enabled)() {
    return body(self)
  }
  let context = ObservationContext::{
    run_id: o.run_id,
    span_id: (o.next_id)(),
    parent_id: self.context.span_id,
  }
  let child = Scope::{ observer: o, context, sequence: self.sequence, }
  let start = (o.monotonic)()
  fn emit(signal : Signal, duration : Double) -> Unit {
    self.sequence.val += 1
    ignore(
      (o.try_record)({
        context,
        sequence: self.sequence.val,
        stage,
        signal,
        wall_seconds: (o.wall)(),
        duration_seconds: duration,
      }),
    )
  }
  emit(Started, 0.0)
  let mut terminal = Signal::Failed
  errdefer emit(terminal, (o.monotonic)() - start)
  let result = body(child) catch {
    error => {
      if error is @execution.Invalid("Cancelled") {
        terminal = Cancelled
      }
      raise error
    }
  }
  emit(Succeeded, (o.monotonic)() - start)
  result
}

///|
pub fn Observation::to_ion(self : Observation) -> @ion.IonValue {
  @execution.record([
    ("profile", @ion.IonValue::string("morphir-observation-v1")),
    ("run_id", @ion.IonValue::string(self.context.run_id)),
    ("span_id", @ion.IonValue::string(self.context.span_id)),
    ("parent_id", @ion.IonValue::string(self.context.parent_id)),
    ("sequence", @ion.IonValue::int(self.sequence)),
    ("stage", @ion.IonValue::string(self.stage.name())),
    (
      "signal",
      @ion.IonValue::string(
        match self.signal {
          Started => "started"
          Succeeded => "succeeded"
          Failed => "failed"
          Cancelled => "cancelled"
          Notice => "notice"
        },
      ),
    ),
    ("wall_seconds", @ion.IonValue::float(self.wall_seconds)),
    ("duration_seconds", @ion.IonValue::float(self.duration_seconds)),
  ])
}

///|
pub fn Observation::to_json(self : Observation) -> Json {
  {
    "profile": "morphir-observation-v1",
    "run_id": self.context.run_id,
    "span_id": self.context.span_id,
    "parent_id": self.context.parent_id,
    "sequence": self.sequence,
    "stage": self.stage.name(),
    "signal": match self.signal {
      Started => "started"
      Succeeded => "succeeded"
      Failed => "failed"
      Cancelled => "cancelled"
      Notice => "notice"
    },
    "wall_seconds": self.wall_seconds,
    "duration_seconds": self.duration_seconds,
  }
}

///|
pub extend Stage with Eq::{equal, not_equal}

///|
pub extend Stage with @debug.Debug::{to_repr}

///|
pub extend Signal with Eq::{equal, not_equal}

///|
pub extend Signal with @debug.Debug::{to_repr}

///|
pub extend Delivery with Eq::{equal, not_equal}

///|
pub extend Delivery with @debug.Debug::{to_repr}
