# Morphir typing tools

`finos/morphir-typing-tools` is not published. It holds the tools and the oracle tests for Morphir IR type inference.

## vspec

`vspec` parses the `vSpec` signature notation of morphir-elm, for example
`vSpec "map2" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "c") ) ] (tVar "c")`. It also converts Elm names to canonical names with `canonical_name`.

## sdkgen

`sdkgen` is an executable. It runs on the native target only, because it reads and writes files.

```shell
moon run pkgs/morphir-typing-tools/sdkgen --target native -- bootstrap pkgs/morphir-sdk/conformance/bindings.json pkgs/morphir-sdk/spec/sdk.scm
```

`bootstrap` writes `pkgs/morphir-sdk/spec/sdk.scm` from `bindings.json`. The file has the hand-written SDK types and the value signatures. Run `bootstrap` once. After that, edit `sdk.scm` by hand. If a name or a construct is unknown, `bootstrap` stops and lists all of them.
