# Independent conformance expectations

`conformance-cases.ion`, profile `morphir-conformance-v1`, version
`2026-10-02.1`, contains directly authored expectations. It is never regenerated
from the MoonBit generator, the SDK, Scheme results, or a Rust evaluator.
The model fixture supplies expressions; the Ion document supplies the oracle.
Changes to expected semantics require a new fixture version and an explanation.

The arithmetic cases use integer calculations beyond JSON's exact numeric range.
Division truncates toward zero: -7 / 3 and 7 / -3 produce -2; -7 / -3 produces 2.
For remainder, -7 - (-2 * 3) is -1 and 7 - (-2 * -3) is 1. Modulus adjusts these
results by the divisor when the signs differ, giving 2 and -2 respectively.
The divisor precedes the dividend in `mod-by` and `remainder-by`.

The ordered call subtracts its second argument from its first. The lazy cases
must avoid a division by zero. Mapping a closure that captures 10 over [1, 2, 3]
produces [11, 12, 13], whose sum is 36. Updating the price retains quantity 3;
the constructor carries 37.5 and matching extracts that payload.

Identity cases retain exact decimal coefficient/exponent, UTF-16 code units, and
IEEE 754 binary64 encodings. The high bit marks negative zero, bit pattern 1 is
the smallest positive subnormal, and the chosen quiet NaN retains its payload.
The text case deliberately contains isolated surrogates, so a UTF-8-only
evaluator cannot claim coverage through replacement characters.

Generated execution, live Scheme evaluation, these independent expectations, and
optional Rust evaluation are distinct evidence lanes. Scheme shares the SDK;
matching it alone does not establish independent arithmetic correctness. An
unavailable or unsupported optional evaluator is recorded as uncovered, never
as a successful comparison. Requiring it fails planning.

## Established Rust intersection

`rust-conformance-cases.ion` uses the same version and independent provenance.
Its literal and identity cases cover signed-64-bit integers, booleans, unit and
text representable as Unicode. `Snow 雪 😀` has UTF-16 units
[83,110,111,119,32,38634,32,55357,56832]. The integer 9007199254740993 exceeds
JSON's exact numeric range but fits the Rust codec. The adapter transports it
as a typed decimal string. The classic IR JSON request stays opaque to Node;
parsing its numeric literals in JavaScript would risk rounding them.

The isolated runnable upstream pin is:

- [finos/morphir source 90f7df0a](https://github.com/finos/morphir/tree/90f7df0a125acc27db45a4b98d2b2883ba0ec471)
- [morphir-rust runtime 15789aef](https://github.com/finos/morphir-rust/tree/15789aef26206b1180c4bcf804bdb1812d1ec91b)
- evaluator JSON protocol `1.1.0-draft.1`, provider `morphir_ir`
- explicit Rust toolchain `1.98.1`; neither stable Rust nor the default MoonBit
  installation is changed

In a separate checkout at that source revision, initialize only
`ecosystem/morphir-rust`, verify its exact revision, then run:

```sh
cargo +1.98.1 test --locked -p morphir-evaluator
cargo +1.98.1 build --locked -p morphir --bin morphir --no-default-features
```

Create a JSON pin local to this provider with `profile:
"morphir-rust-evaluator-pin-v1"`, the protocol above, `sourceRevision`,
`runtimeRevision`, and `binaryIdentity` equal to the built executable's SHA-256.
Record the build command, compiler version and host alongside that pin. The
adapter validates declared revisions and actual binary/helper identities;
source/build provenance belongs to the caller's controlled acquisition process.
It never downloads or chooses a compatible revision implicitly.

The established IR intersection is SDK-free scalar literal and identity
bodies. All definitions are checked, not only reachable entries. The upstream
runtime has broader draft support, but this adapter advertises only its tested
intersection. Before execution, classic-v3 migration must survive serialization,
reading and migration back to the original fully typed IR with exact equality.
Unknown envelope annotations, metadata or provenance cannot be dropped to make
conversion pass. The richer pricing model is explicitly unsupported by Rust;
its independent and Scheme coverage remains required.

Malformed protocol/version, cardinality, call identity, status, output type or
receipt identity fails the Rust comparison. A runtime `error` status retains
its explicit code as `conformance.rust_runtime_error`, never an invented model
error. Missing binaries are unavailable; unsupported types, integer range,
unpaired surrogates and lossy IR conversion are uncovered. Requiring any of
these fails planning. Mock transport tests exercise codec rejection and a live
comparison disagreement; they do not count as Rust execution evidence.
