# Ion field projection

`project(value, JSON|OTLP, policy=Reject)` converts one already-redacted Ion
field. It has no clocks, I/O, collector configuration or exporter dependencies.
Apply payload-capture and redaction policies before calling it.

The default rejects any value that the destination cannot represent. `Drop`
omits the whole field and reports `dropped=1, lossy=1`, with a JSON Pointer and
reason. Arrays never lose members or change positions. `Envelope` writes the
complete value into a versioned `morphir-ion-field-v1` binary Ion wrapper and
reports `encoded=1, lossy=0`. JSON uses explicit base64 encoding; OTLP uses a
key/value wrapper containing a `bytesValue`. Recover that field with the Ion
binary reader, rather than interpreting it as an ordinary string.

JSON numbers accept integers only within ±9007199254740991. OTLP's `intValue`
uses a decimal string within signed 64-bit bounds, as required by its protobuf
JSON encoding. Plain OTLP blobs use `bytesValue`. Exact decimals, annotations,
typed nulls, clobs, timestamps, symbols, s-expressions and duplicate struct
fields require an explicit policy. Nonfinite floats and negative zero also
require preservation rather than relying on a consumer's JSON normalization.
No policy bypasses depth, node or size limits.

The result is a field value and conversion accounting, not an OTLP request or a
collector integration claim. Task 6 supplies the native adapter/collector gate.
The field shapes follow the [OTLP JSON encoding](https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding)
and [AnyValue contract](https://github.com/open-telemetry/opentelemetry-proto/blob/main/opentelemetry/proto/common/v1/common.proto).
