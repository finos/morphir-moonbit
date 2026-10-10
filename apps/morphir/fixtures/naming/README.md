# Pre-change naming checkpoint

`pre-readable.ion` is retained output from the installed Boolean library gate
qualified at `da0b9d7c408e7eb81f1b011f6ec0b9a8ab389e9c` and landed in
[PR #55](https://github.com/finos/morphir-moonbit/pull/55), squash
`67bea18dc8f07543639c7b3c41335c1de0e317c9`. Its source is
`pre-readable.mbt`. This fixture predates readable semantic naming and retains
`source-657175616c`, `source-6e6f` and `source-796573` entry IDs.

`pre-readable.json` pins the artifact bytes, compiler/parser profile and
independently authored Boolean results. The current acceptance gate imports the
stored checkpoint, never recompiles it to produce a historical identity, and
compares its behavior against the retained source. Hashes identify the retained
bytes; they do not establish provider trust.

These repository test fixtures are excluded from the npm package. The gate runs
against the packed CLI from an empty working directory and supplies the fixture
explicitly. Do not update it when current naming policy changes.
