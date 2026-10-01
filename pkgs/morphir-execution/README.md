# Morphir execution contracts

Portable, versioned invocation values and observations. This module has no process,
filesystem, clock or global logging dependencies. The engine accepts a host-owned
execution provider and an optional evaluator. Generated drivers import this module
and the generated library.

The initial `morphir-invocations-v1` profile supports exact integers, booleans and
Unit. Ion text and binary encode integers directly, booleans directly and Unit as
`morphir_unit::null`. JSON encodes values as `{"type":"int","value":"42"}`,
`{"type":"bool","value":true}` or `{"type":"unit"}`. JSON integers must be strings.
Unsupported types and profile versions are rejected.

```ion
{
  profile: "morphir-invocations-v1",
  calls: [{
    id: "difference",
    entry: "calls:main#subtract",
    arguments: [9007199254741035, 9007199254740993]
  }]
}
```

Every suite needs distinct, nonempty call IDs and at least one call. The initial
budgets are 1 MiB encoded input, 1,000 calls, and 64 arguments per call. These are
acceptance limits, not a streaming parser guarantee. Private or unsupported entry
points, arity and types are checked by the engine before provider acquisition.

The observation interface has a cheap disabled guard, explicit context and
host-supplied clocks and IDs. Sinks return a delivery status without raising.
Required execution results never pass through this interface. Default observation
fields contain no model arguments, results, source text, paths or environment.
The current local host adapter records stage observations and bounded duration
histograms. Native OpenTelemetry integration remains a later acceptance gate.
