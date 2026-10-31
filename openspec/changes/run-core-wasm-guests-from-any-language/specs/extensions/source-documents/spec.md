# Spec Delta

## Purpose

Defines how `morphir extension compile` turns a source file or a source directory into the documents of one MEP
compile request, so that a multi-module project in any claimed language reaches the guest as one bounded tree.

## ADDED Requirements

### Requirement: Directory input
`compile` SHALL accept a directory as its input. The CLI SHALL walk it and include each regular file whose name
ends with a file extension that the selected language claims. It SHALL read no other files except ignore files.
The walk SHALL skip every hidden directory (a name that starts with `.`) and `.git`, `.mooncakes`, `_build`,
`node_modules` and `.venv`. A tree that gives no document SHALL be refused with `extension.input_invalid`,
exit 2.

#### Scenario: Gleam project tree
- **WHEN** a user compiles `src` that holds `shared/numbers.gleam`, `app/money.gleam`, `app/orders.gleam` and
  `README.md`, with a guest that claims `.gleam`
- **THEN** the request has three documents and `README.md` is not read

#### Scenario: Skipped directories
- **WHEN** a user compiles `src` that holds `app/money.gleam`, `.cache/a.gleam`, `node_modules/x/b.gleam` and
  `_build/c.gleam`
- **THEN** the request has only the document for `app/money.gleam`, and the walk does not list `.cache`,
  `node_modules` or `_build`

#### Scenario: Directory with no claimed files
- **WHEN** a user compiles a directory that has only `.md` files
- **THEN** the command exits 2 with `extension.input_invalid` and no guest starts an operation

### Requirement: Ignore files in the source walk
The directory walk SHALL honor each `.gitignore` and `.morphirignore` file in a walked directory, with Git's
`gitignore` syntax and nesting rules: the patterns of a file apply below its directory, and `!` includes a path
again. The walk SHALL NOT descend into an ignored directory, read an ignored file or refuse an ignored link or
special file. No ignore file SHALL include again a directory that "Directory input" skips. An ignore file above
1 MiB SHALL be refused with `extension.input_invalid`.

#### Scenario: Ignored build directory
- **WHEN** a user compiles `shop`, which holds a `.gitignore` with the line `/build`, `src/app/money.gleam` and
  `build/packages/gleam_stdlib/src/gleam/list.gleam`
- **THEN** the request has the document for `src/app/money.gleam`, no document from `build`, and the walk does not
  list `build`

#### Scenario: Nested ignore file
- **WHEN** `src/app/.gitignore` has the line `generated.gleam`, and the tree has `src/app/generated.gleam` and
  `src/generated.gleam`
- **THEN** `src/app/generated.gleam` is not read and `src/generated.gleam` is a document

#### Scenario: Morphir-only exclusion
- **WHEN** the walked directory holds a `.morphirignore` with the line `test/`, and `test/money_test.gleam` is a
  file that Git tracks
- **THEN** `test/money_test.gleam` is not read

#### Scenario: Ignored link
- **WHEN** the walked directory holds a `.gitignore` with the line `/vendor`, and `vendor` is a symbolic link to
  another directory
- **THEN** the walk does not refuse the link and does not follow it

### Requirement: Precedence of ignore files
When patterns of several ignore files match one path, the last matching pattern SHALL decide. The patterns of a
deeper directory SHALL come after those of a higher directory, and in one directory the patterns of
`.morphirignore` SHALL come after those of `.gitignore`. Thus a `!` pattern in `.morphirignore` includes again a
path that `.gitignore` excludes. As in Git, a path SHALL NOT be included again when a parent directory of it is
excluded.

#### Scenario: Morphir ignore file includes a file again
- **WHEN** the walked directory holds a `.gitignore` with the line `*_gen.gleam` and a `.morphirignore` with the
  line `!src/model_gen.gleam`, and the tree has `src/model_gen.gleam` and `src/other_gen.gleam`
- **THEN** `src/model_gen.gleam` is a document and `src/other_gen.gleam` is not read

#### Scenario: Excluded parent directory
- **WHEN** a `.gitignore` has the line `gen/` and a `.morphirignore` in the same directory has the line
  `!gen/model.gleam`
- **THEN** `gen/model.gleam` is not read, because its parent directory is excluded

### Requirement: Only ignore files in the tree
The CLI SHALL read only the ignore files in the walked tree. It SHALL NOT read a global Git excludes file or
`.git/info/exclude`, so that the documents do not depend on the user's Git configuration.

#### Scenario: Global excludes do not apply
- **WHEN** the user's global Git excludes file has the line `*.gleam`, and the tree has no ignore file
- **THEN** every `.gleam` file in the tree is a document

### Requirement: Relative document URIs
Each document URI SHALL be the file's path relative to the source base, with `/` separators. The source base
SHALL be `--source-base` when given, else the current directory. The input SHALL be at or below the source base.
The request SHALL NOT contain `sources.root` or an absolute host path.

#### Scenario: Run from the project directory
- **WHEN** a user in `/work/shop` compiles `src` and the tree has `src/app/money.gleam`
- **THEN** that document has the URI `src/app/money.gleam` and the request has no `sources.root`

#### Scenario: Explicit source base
- **WHEN** a user compiles `/work/shop/src` with `--source-base /work/shop`
- **THEN** the URIs are the same as in the scenario above

#### Scenario: Input outside the source base
- **WHEN** a user compiles `/other/src` with `--source-base /work/shop`
- **THEN** the command exits 2 with `extension.input_invalid` and the message names the source base

### Requirement: Safe URI segments
Each URI segment SHALL be non-empty and SHALL NOT be `.` or `..`. A segment SHALL be percent-encoded as an RFC 3986
path segment, so that `%`, `?`, `#`, `\`, `:`, spaces, control characters and non-ASCII characters do not appear
raw. Two files that give the same URI SHALL be refused with `extension.input_invalid`.

#### Scenario: File name with a space
- **WHEN** the tree has `src/my module.gleam`
- **THEN** its URI is `src/my%20module.gleam`

#### Scenario: Plain names stay the same
- **WHEN** a file path has only letters, digits, `-`, `.`, `_` and `~` in each segment
- **THEN** its URI equals its relative path

### Requirement: Single file input
A single file input SHALL give one document. Without `--source-base`, its URI SHALL follow the earlier rule: a clean
relative path keeps its nesting, and an absolute path or a path with `..` gives only the file name. With
`--source-base`, the directory rule SHALL apply.

#### Scenario: MoonBit guest and one file
- **WHEN** a user compiles `src/main.mbt` with the MoonBit guest
- **THEN** the request has one document with URI `src/main.mbt` and `languageId: "moonbit"`, as before

### Requirement: Deterministic order
Documents SHALL be sorted by URI in byte order. Two runs over the same tree SHALL give the same request bytes.

#### Scenario: Same tree twice
- **WHEN** a user compiles the same unchanged tree twice with the same options
- **THEN** the two `compileModel` requests are byte for byte the same

### Requirement: Tree limits
The CLI SHALL refuse a tree with more than 1,024 documents, a file larger than 1 MiB, more than 2 MiB of source
bytes in total, a depth of more than 32 directories or more than 16,384 walked entries, with
`extension.input_invalid`, exit 2, and a message that names the limit and its value. The framed request SHALL still
fit in 4 MiB, or the command SHALL fail with `extension.request_limit`. All checks SHALL happen before an operation
session starts.

#### Scenario: Too many documents
- **WHEN** a tree has 1,025 `.gleam` files
- **THEN** the command exits 2 with `extension.input_invalid`, the message names the limit of 1,024 documents,
  and no operation session starts

#### Scenario: Request too large after encoding
- **WHEN** the documents fit in 2 MiB but the framed request is larger than 4 MiB
- **THEN** the command exits 2 with `extension.request_limit`

### Requirement: Links and special files
The walk SHALL NOT follow symbolic links. A symbolic link or a special file anywhere in the tree, unless the walk
skips or ignores it, SHALL be refused with `extension.input_invalid`, and the message SHALL name its relative path.

#### Scenario: Link inside the tree
- **WHEN** `src/vendor` is a symbolic link to another directory
- **THEN** the command exits 2 with `extension.input_invalid` and the message names `src/vendor`

### Requirement: UTF-8 source text
Each included file SHALL be valid UTF-8. A file that is not SHALL be refused with `extension.input_invalid`,
exit 2, and the message SHALL name its URI.

#### Scenario: Latin-1 file
- **WHEN** an included file has bytes that are not valid UTF-8
- **THEN** the command exits 2 with `extension.input_invalid` and the message names the URI of that file

### Requirement: Multi-document permission
A request with more than one document SHALL be sent only when the guest claims `frontend.multiDocument: true`.
Otherwise the command SHALL exit 2 with `extension.capability_unavailable` before the operation session.

#### Scenario: MoonBit guest and a tree
- **WHEN** a user compiles a directory with two `.mbt` files and the MoonBit guest, which does not claim
  multi-document support
- **THEN** the command exits 2 with `extension.capability_unavailable` and no operation session starts

### Requirement: Context digest unchanged
The context digest SHALL stay the SHA-256 of the package name and options. The documents SHALL NOT change it.

#### Scenario: Same options, different trees
- **WHEN** two compiles use the same package and options but different trees
- **THEN** both requests carry the same `contextDigest`
