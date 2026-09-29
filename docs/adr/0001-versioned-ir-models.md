# Keep historical IR models explicit

Each IR major version has a distinct model and JSON codec. The unversioned API follows the latest supported model, initially v4, as requested by the maintainer; consumers requiring a fixed representation use an explicit version package. This keeps historical encodings stable while allowing the current model to evolve, at the cost of maintaining explicit conversions.

Elm's versioned codecs are the encoding authority for v1–v3, including their differences from the published JSON schemas. The finos/morphir specification defines v4 and the v3.1 Specs extension. Migrations refuse information they cannot represent rather than silently dropping it.
