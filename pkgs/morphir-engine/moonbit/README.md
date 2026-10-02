# MoonBit source adapter

This package connects the pure [Boolean frontend](../../morphir-moonbit-frontend/README.md)
to the engine's rich source callback. Applications opt in explicitly:

```moonbit
let engine = @engine.Engine::new()
@moonbit_frontend.register(engine)
```

Import `finos/morphir-engine/moonbit` as `moonbit_frontend`. The adapter registers
`moonbit` for `.mbt` files with profile `moonbit-model-bool-v1`, parser 0.4.1 and
lexer 0.4.0 descriptors. `register` accepts optional `limits` for source parsing and
lowering and `unit_limits` for rich envelope admission. Registration conflicts fail.
Engine core stays independent of the parser package; the Morphir CLI opts in here.

The callback preserves native Ion metadata, annotations and provenance, forwards
cancellation and translates source diagnostics into `SourceFrontendError::Rejected`.
The engine supplies canonical package/module names and validates the logical unit ID
and metadata ownership. Checkpoint and generation pipelines retain the rich unit.
Legacy text output requires a separate explicit projection contract.

No file, process, acquisition or compiler operations happen in this adapter.
Installed source-to-execution acceptance and A2 extension delivery are separate
roadmap slices. See the [CLI example](../../../apps/morphir/README.md#moonbit-source-models).

```sh
moon test -p finos/morphir-engine -p finos/morphir-engine/moonbit --target all
```
