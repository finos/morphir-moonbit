///|
pub struct TelemetrySession {
  priv sequence : Ref[Int]
  priv metrics : Map[String, (Int, Double, Array[Int])]
  priv records : Array[@observe.Observation]
  priv path : String?
  priv format : String
  priv run_id : String
  priv mut next : Int
  priv mut dropped : Int
  priv mut closed : Bool
}

///|
pub fn TelemetrySession::new(
  path : String?,
  format? : String = "ion-binary",
) -> TelemetrySession raise {
  if !["ion-binary", "ion-text", "json-lines", "text"].contains(format) {
    raise @config.Invalid("observability.unsupported_format")
  }
  // No I/O occurs until flush. Host clocks/IDs are only used for enabled sessions.
  let run_id = if path is Some(_) { @platform.observation_id() } else { "" }
  {
    sequence: Ref(0),
    metrics: Map([]),
    records: [],
    path,
    format,
    run_id,
    next: 0,
    dropped: 0,
    closed: false,
  }
}

///|
pub fn TelemetrySession::observer(self : TelemetrySession) -> @observe.Observer {
  {
    enabled: fn() { self.path is Some(_) && !self.closed },
    try_record: fn(record) {
      if self.closed {
        return @observe.Unavailable
      }
      if record.signal is Succeeded ||
        record.signal is Failed ||
        record.signal is Cancelled {
        let key = record.stage.name()
        let (count, total, buckets) = self.metrics
          .get(key)
          .unwrap_or((0, 0.0, [0, 0, 0, 0, 0, 0, 0]))
        let bounds = [0.001, 0.01, 0.1, 1.0, 10.0, 60.0]
        let mut bucket = 6
        for i = 0; i < bounds.length(); i = i + 1 {
          if record.duration_seconds <= bounds[i] {
            bucket = i
            break
          }
        }
        buckets[bucket] += 1
        self.metrics[key] = (
          count + 1,
          total + record.duration_seconds,
          buckets,
        )
      }
      if self.records.length() >= 2048 {
        self.dropped += 1
        return @observe.Dropped
      }
      self.records.push(record)
      @observe.Accepted
    },
    monotonic: @platform.monotonic_seconds,
    wall: @platform.wall_seconds,
    next_id: fn() {
      self.next += 1
      self.next.to_string()
    },
    run_id: self.run_id,
    sequence: self.sequence,
  }
}

///|
/// Typed compatibility adapter. Free-text event contents are excluded from logs.
pub fn TelemetrySession::event(self : TelemetrySession, event : Event) -> Unit {
  let stage = match event {
    Phase(_) => @observe.Legacy
    Diagnostic(_) => @observe.Execute
    Generated(_) => @observe.Generate
    Validated(_) => @observe.Build
    Published(_) => @observe.Execute
  }
  let o = self.observer()
  if (o.enabled)() {
    self.sequence.val += 1
    ignore(
      (o.try_record)({
        context: { run_id: self.run_id, span_id: "", parent_id: "", },
        sequence: self.sequence.val,
        stage,
        signal: @observe.Notice,
        wall_seconds: @platform.wall_seconds(),
        duration_seconds: 0.0,
      }),
    )
  }
}

///|
/// Bounded local sink. Failures are reported directly on stderr, never recursively.
pub fn TelemetrySession::flush(self : TelemetrySession) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  guard self.path is Some(path) else { return }
  try {
    // Three previous runs retained. Every file is bounded by queue capacity.
    for i = 3; i >= 1; i = i - 1 {
      let old = if i == 1 { path } else { path + "." + (i - 1).to_string() }
      let dest = path + "." + i.to_string()
      if @platform.kind(old) != 0 {
        if @platform.kind(dest) != 0 {
          @platform.remove_file(dest)
        }
        @platform.rename(old, dest)
      }
    }
    match self.format {
      "ion-binary" =>
        @platform.write_bytes(
          path,
          @ion_binary.write_binary(
            self.records.map(r => r.to_ion()) + [self.metrics_ion()],
          ),
        )
      "ion-text" =>
        @platform.write(
          path,
          self.records.map(r => @ion_text.write_ion(r.to_ion())).join("\n") +
          "\n",
        )
      "json-lines" =>
        @platform.write(
          path,
          self.records.map(r => r.to_json().stringify()).join("\n") + "\n",
        )
      _ =>
        @platform.write(
          path,
          self.records
          .map(r => r.stage.name() + " " + r.to_json().stringify())
          .join("\n") +
          "\n",
        )
    }
    if self.dropped > 0 {
      @platform.stderr(
        "warning: observability dropped " +
        self.dropped.to_string() +
        " records\n",
      )
    }
  } catch {
    _ => @platform.stderr("warning: observability sink unavailable\n")
  }
  self.records.clear()
}

///|
pub fn TelemetrySession::metrics(self : TelemetrySession) -> Json {
  let names = self.metrics.keys().collect()
  names.sort()
  {
    "profile": "morphir-metrics-v1",
    "dropped": self.dropped,
    "stages": names.map(name => {
      let (count, total, buckets) = self.metrics[name]
      (
        {
          "stage": name,
          "count": count,
          "duration_seconds_sum": total,
          "duration_seconds_buckets": buckets,
        } : Json)
    }),
  }
}

///|
fn TelemetrySession::metrics_ion(
  self : TelemetrySession,
) -> @ion.IonValue raise {
  receipt_ion_metrics(self.metrics())
}

///|
fn receipt_ion_metrics(value : Json) -> @ion.IonValue raise {
  match value {
    Number(n, ..) => @ion.IonValue::float(n)
    Array(a) => @ion.IonValue::list(a.map(receipt_ion_metrics))
    Object(f) => {
      let names = f.keys().collect()
      names.sort()
      @protocol.record(names.map(n => (n, receipt_ion_metrics(f[n]))))
    }
    _ => receipt_ion(value)
  }
}
