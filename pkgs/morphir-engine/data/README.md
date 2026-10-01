# Portable pipeline data boundaries

`finos/morphir-engine/data` supplies registered codecs for a typed `IRUnit` and
engine-owned Ion metadata. It is callable from a memory snapshot on native, JS,
WASM and WASM-GC. It performs no filesystem, network, process or compiler effects.

Morphir JSON remains supported. `morphir-json` reads the existing versioned JSON
schema and explicitly migrates it to current IR. `ion-text` and `ion-binary` read
the profile below into the same typed contract. `Registry::checkpoint` defaults
to Ion binary. Selecting JSON as a source does not change that default.

```moonbit
let registry = @data.Registry::new()
let unit = registry.decode("morphir-json", {
  unit_id: "Pricing",
  content: Text(json_source),
})
let checkpoint = registry.checkpoint(unit) // Binary(Bytes), never UTF-8 text
let restored = registry.decode("ion-binary", {
  unit_id: "Pricing",
  content: checkpoint,
})
```

The module depends on the exact registry release `moonrockz/ion@0.3.0`, using its
synchronous annotated value, text and binary packages. Async streaming is not
part of this portable callback contract.

## IR-unit profile

The initial `morphir-pipeline-v1` contract is `ir-unit`. It keeps the profile
version separate from the nested IR format version and Ion 1.0 encoding. Text and
binary carry the same value model. The source snapshot supplies an expected
logical unit ID; an envelope containing another ID is refused.

```ion
morphir_pipeline::{
  profile: "morphir-pipeline-v1",
  contract: "ir-unit",
  unit_id: "Pricing",
  ir: {
    formatVersion: 4,
    distribution: {
      Library: {
        packageName: "pricing",
        dependencies: {},
        def: {modules: {}}
      }
    }
  },
  metadata: [
    {node_id: "value:Pricing.quote/body", data: hint::12.340d0}
  ]
}
```

An envelope must contain the `morphir_pipeline` annotation. Additional ordered
annotations are retained. Schema records reject duplicate/unknown fields.
Metadata records have unique, nonempty node IDs and an unrestricted Ion `data`
value, subject to budgets. That value retains annotations, duplicate struct
fields, exact decimals, typed nulls, timestamps, symbols, blobs/clobs and other
Ion kinds. IDs are caller-supplied semantic identities, not array positions or
filesystem paths. This slice supports identity processing. Structural rewrites
need the separately planned lineage and metadata policy contract.

The nested `ir` follows the supported Morphir IR wire shape. It reuses the existing
validated versioned IR codecs through an explicit schema mapping. Rich metadata
never goes through a JSON projection or the JSON-shaped `Data` extension model.
Native Ion integers retain arbitrary magnitude. A numeric JSON lexeme whose
spelling could change, including `-0`, decimal scale or exponents, has the explicit
representation `morphir_json_number::"1e-400"`. It is validated as a JSON number
before semantic decoding. Canonical integers use native Ion integers. Decimal
literal strings retain their original spelling under the existing IR schema.

Unsupported annotations or richer kinds inside the semantic `ir` subtree are
refused, rather than silently discarded. Put rich engine metadata in `metadata`.
This first profile does not automatically extract annotations from arbitrary IR
nodes or extend the current semantic IR vocabulary. JSON object field order is
not a semantic identity; the Ion semantic subtree is emitted in sorted field
order for deterministic checkpoints.

## Selection and diagnostics

`Registry::register` adds a named codec with typed decode/encode callbacks.
Duplicate IDs fail. A binary codec requires `Binary(Bytes)` and a text codec
requires `Text(String)`; there is no implicit encoding or format fallback.
Callbacks are trusted local components and receive the configured limits.
Registry checks also apply to their accepted results and output byte sizes.

`morphir-json` writes standard current Morphir JSON. It refuses units containing
engine metadata or additional envelope annotations with `data.lossy_conversion`.
A JSON-only component can use this semantic representation, but preserving rich
engine metadata around its result requires the later boundary/lineage adapter.
This package does not claim that the adapter or the project CLI already exists.

Errors have a stable code and detail in `BoundaryError::Invalid`. Existing IR
codec/version diagnostics are retained, including migration failures. Boundary
codes include `data.profile_mismatch`, `data.unit_mismatch`,
`data.encoding_mismatch`, `data.duplicate_field`, `data.profile_value_unsupported`,
`data.symbol_catalog_missing`, `data.unknown_codec`, and `data.codec_conflict`.
Unresolved shared-symbol imports require a catalog and fail explicitly in this
self-contained profile. Invalid Unicode is refused rather than replaced on write.

## Budgets and acceptance

Defaults are 4 MiB per source/output, depth 128, and 100,000 values/annotations.
Byte limits run before decoding and after encoding. Tree budgets apply to accepted
envelopes and before Ion emission. The synchronous Ion parsers construct a value
tree before its depth/value validation; these budgets do not promise bounded
parser allocation, interruption, or a streaming security sandbox. Parser-level
depth/number limits and host streaming are separate work. Public typed IR is
trusted application data and uses the existing IR traversal/codec rules.

The focused tests verify equivalent JSON/Ion input, migration, semantic IR and
exact-number preservation, rich metadata text/binary round trips, loss refusal,
registration conflicts, malformed input, identity checks, and byte/tree budgets
on all four portable targets:

```sh
mise exec -- moon test -p finos/morphir-engine/data --target all
```

An in-memory example is runnable with:

```sh
mise exec -- moon run pkgs/morphir-engine/data/examples --target native
```

Filesystem byte I/O, configured CLI checkpoints, arbitrary annotated IR imports,
structural transformation lineage, generated projects and build validation are
later tasks in the E1 beads plan.
