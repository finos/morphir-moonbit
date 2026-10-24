# Typed pricing model

`typed-pricing.json` is normalized v4 JSON exported from
`finos/morphir-moonbit/fixtures.pricing()` in `pkgs/morphir-moonbit/fixtures/pricing.mbt`.
It uses the merged E2 pricing and rich-boundary fixture, including Decimal,
UTF-16, Float64, Maybe/Result and custom constructors. Browser and desktop
workflow checks import this file and evaluate its real definitions.

Select `Quotes.total` in Model Explorer and use **Typed invocation**; the
[workbench guide](../README.md) contains arguments and the expected result.
