# Classic IR naming types

This package contains the Classic IR naming API contributed by PR #11:
`Name`, `Path`, `QName`, `ModuleName`, `PackageName`, and `FQName`, plus
validated `NameToken` values. The implementation lives under
`finos/morphir-core/ir/classic` and `finos/morphir-core/ir/common`.

The versioned executable IR models and JSON codecs live separately in
`finos/morphir-ir`. This package is available for clients that use the Classic
naming API; it does not replace the `morphir-ir` versioned models.
