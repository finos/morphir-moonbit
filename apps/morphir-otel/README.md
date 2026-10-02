# Native OpenTelemetry adapter

This optional host component converts bounded `morphir-observation-v1` and
`morphir-metrics-v1` **native Ion batches** into OpenTelemetry SDK spans, correlated
logs and cumulative counters. It builds separately from `moon.work`; portable
engine, driver and observation packages do not import an exporter, async socket
stack or SDK provider.

The supported acceptance hosts are Linux/x64 and macOS/arm64. The supported
transport is **OTLP HTTP/JSON without compression**. gRPC, gzip, zstd and
HTTP/protobuf are not advertised by this adapter. The upstream package contains
additional API choices; this adapter accepts only the transport covered by its
integration gate.

## Build explicitly

```sh
MOON_HOME=/pinned/stable/home \
MORPHIR_OTEL_OUTPUT=/private/native-otel \
mise run setup:native-otel
```

Setup verifies the compiler version and downloads every dependency archive in
[dependencies.json](dependencies.json), checking SHA-256 before extraction. It
builds a temporary workspace with all dependencies supplied as local members,
using `--frozen`, then records compiler, bundled core, source, binary and archive
identities in `pin.json`. It never changes the default compiler or workspace
registry. Node 24.21.0 and Python 3 are setup dependencies; Python only extracts
verified ZIP archives. Runtime needs the built binary and packaged Node helper.

The receipt describes a caller-controlled build; runtime verifies the binary
identity, accepted OpenTelemetry archive and host. It does not attest that a
third party followed these build instructions.

## Select the adapter

Use the normal `execute`, `verify` or `conform` options, then add:

```sh
--telemetry-adapter opentelemetry-native \
--otel-binary /private/native-otel/morphir-otel \
--otel-pin /private/native-otel/pin.json \
--otel-helper /installed/@morphir/morphir/build-provider/telemetry.mjs \
--otel-endpoint http://127.0.0.1:4318 \
--otel-protocol http/json --otel-flush-timeout 1000
```

The endpoint is an explicit root without a trailing slash. The worker appends
`/v1/traces`, `/v1/logs` and `/v1/metrics`. No endpoint or exporter is selected by
default, including when ambient `OTEL_*` variables exist. The native worker's
`OTEL_*` environment is cleared so ambient headers, endpoint, compression and
resource detectors cannot change this configuration. Authentication headers are
not configured by this adapter.

Local file logging and the native adapter are exclusive CLI sink selections.
Dry-run checks option syntax and reports a deferred capability check without
opening the binary, helper or pin, creating logs, building code or exporting.
An unavailable selected adapter or bad binary pin fails planning; there is no
fallback to a local sink. A runtime delivery failure is optional observation
health: stderr reports it, undelivered records are counted, and required semantic
receipts and stdout framing retain their result.

The host drains at most 2,048 observations plus one bounded metrics record and
4 MiB into a supervised worker. A 1–5,000 ms allowance covers the entire batch,
including all three signal requests; process containment has a separate bounded
termination allowance. Queued work is not retried implicitly. Trace and log
identity comes from the portable observations; metrics keep bounded stage,
target, provider and outcome dimensions. Payloads and arguments are excluded.
Metric streams with distinct attributes may appear as multiple OTLP metric
entries with the same name; capture assertions aggregate those data points.

## Integration and baseline evidence

```sh
MOON_HOME=/pinned/stable/home \
MORPHIR_OTEL_BINARY=/private/native-otel/morphir-otel \
MORPHIR_OTEL_PIN=/private/native-otel/pin.json \
MORPHIR_TELEMETRY_RECEIPTS=.dev/telemetry-receipts \
mise run test:native-telemetry
```

The gate installs the packed npm CLI and runs it outside the checkout. A local
HTTP capture endpoint validates real exporter payloads, correlation, all 23 call
spans, metric counts, absence of model payloads and bounded flush failure. This
is a capture-endpoint integration test, not a claim of interoperability with a
particular Collector release or vendor. It is separate from portable tests.

Three paired CLI runs record disabled versus local Ion instrumentation on the
same 23-case model. The workload includes a fresh generated build/session each
run; results and environment are retained. The median delta and observed spread
supply a provisional absolute budget. **No performance threshold is enforced**:
repeat baselines across CI hosts before adopting a regression limit. These
measurements do not isolate in-process observer cost or measure network export
latency.

Primary references: [upstream MoonBit package](https://github.com/moonbit-community/opentelemetry.mbt),
[OTLP specification](https://opentelemetry.io/docs/specs/otlp/).
