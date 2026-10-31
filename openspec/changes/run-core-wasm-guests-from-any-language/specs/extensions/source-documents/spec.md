# Spec Delta

## Purpose

Defines how `morphir extension compile` turns a source file or a source directory into the documents of one MEP
compile request, so that a multi-module project in any claimed language reaches the guest as one bounded tree.

## ADDED Requirements

### Requirement: Directory input
`compile` SHALL accept a directory as its input. The CLI SHALL walk it and include each regular file whose name
ends with a file extension that the selected language claims. It SHALL NOT read other files. A tree that gives no
document SHALL be refused with `extension.source_required`.

#### Scenario: Gleam project tree
- **WHEN** a user compiles `src` that holds `shared/numbers.gleam`, `app/money.gleam`, `app/orders.gleam` and
  `README.md`, with a guest that claims `.gleam`
- **THEN** the request has three documents and `README.md` is not read

#### Scenario: Directory with no claimed files
- **WHEN** a user compiles a directory that has only `.md` files
- **THEN** the command exits 2 with `extension.source_required` and no guest starts an operation

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
- **THEN** the command exits 2 with `extension.invalid_source_path` and names the source base

### Requirement: Safe URI segments
Each URI segment SHALL be non-empty and SHALL NOT be `.` or `..`. A segment SHALL be percent-encoded as an RFC 3986
path segment, so that `%`, `?`, `#`, `\`, `:`, spaces, control characters and non-ASCII characters do not appear
raw. Two files that give the same URI SHALL be refused with `extension.invalid_source_path`.

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
`extension.resource_limit` and the name of the limit. The framed request SHALL still fit in 4 MiB, or the command
SHALL fail with `extension.request_limit`. All checks SHALL happen before an operation session starts.

#### Scenario: Too many documents
- **WHEN** a tree has 1,025 `.gleam` files
- **THEN** the command exits 2 with `extension.resource_limit: documents` and no operation session starts

#### Scenario: Request too large after encoding
- **WHEN** the documents fit in 2 MiB but the framed request is larger than 4 MiB
- **THEN** the command exits 2 with `extension.request_limit`

### Requirement: Links and special files
The walk SHALL NOT follow symbolic links. A symbolic link or a special file anywhere in the tree SHALL be refused
with `extension.invalid_source_path`, and the message SHALL name its relative path.

#### Scenario: Link inside the tree
- **WHEN** `src/vendor` is a symbolic link to another directory
- **THEN** the command exits 2 with `extension.invalid_source_path` and names `src/vendor`

### Requirement: UTF-8 source text
Each included file SHALL be valid UTF-8. A file that is not SHALL be refused with
`extension.invalid_source_encoding`, and the message SHALL name its URI.

#### Scenario: Latin-1 file
- **WHEN** an included file has bytes that are not valid UTF-8
- **THEN** the command exits 2 with `extension.invalid_source_encoding` and names that file

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
