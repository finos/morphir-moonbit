# Morphir Engine

A portable engine for transforming a file, directory, project or workspace:

```text
Host files → frontend → current Morphir IR → Scheme transforms → backend → artifacts
```

The engine handles discovery, manifests, configuration and diagnostics. The host
owns I/O. Its synchronous `read`, `exists` and recursive `list` callbacks can read
an editor snapshot, a filesystem or a cache populated by asynchronous I/O.
The engine returns artifacts; the caller chooses how to persist or publish them.

## Run the example

From the repository root:

```sh
mise exec -- moon run pkgs/morphir-engine/examples --target native
# Also supported: --target js, --target wasm, --target wasm-gc
```

This runs a project from a memory host, applies its configuration, emits an IR
artifact and executes its `main` entry. The `apps/morphir` CLI remains a scaffold;
it does not yet expose engine commands or a filesystem adapter.

## Embed the engine

Declare `finos/morphir-engine@0.1.0` in your module and import it as `engine`.

```moonbit
let host = @engine.Host::memory(Map::from_array([
  ("demo/morphir.json", "{\"name\":\"demo\",\"sourceDirectory\":\"src\"}"),
  ("demo/src/main.scm", "(* 6 7)"),
]))
let engine = @engine.Engine::new()
let report = engine.run(host, @engine.Project("demo"))
// report.artifacts[0].path == "demo/dist/main.ir.json"
```

`Report` contains `artifacts`, `diagnostics` and `processed` (successful artifact
count). `successful()` means no diagnostics. Diagnostics identify the path,
stage and error detail. A failed file produces no artifact; other files continue.
Output collisions produce a diagnostic and retain only the first artifact.
Check the whole report before publishing a build that must be atomic.

| Input | Discovery |
| --- | --- |
| `File(path)` | One file, regardless of extension; parent directory supplies config |
| `Directory(root)` | Recursively listed files matching the selected frontend extensions |
| `Project(root)` | `morphir.json` supplies `name` and `sourceDirectory` (defaults: `user`, `src`) |
| `Workspace(root)` | `morphir-workspace.json` lists project directories in `projects` |

Project manifests must exist. The engine uses only their name and source directory;
it does not implement Elm `exposedModules`, dependency resolution or cross-file
linking. Each source yields a separate IR distribution/artifact. A Scheme module's
name comes from its source-relative path without the final extension. Nested source
paths are retained in output paths. References to other implementations can be
resolved by loading them together in a Scheme runtime.

Workspace manifest:

```json
{"projects": ["packages/orders", "packages/pricing"]}
```

Workspace project order is retained; files within each project are sorted and
deduplicated. Duplicate project entries are ignored. Configuration and manifest
files at the project root, plus the output subtree, are excluded from discovery.

## Script configuration

Place `morphir.config.scm` at the workspace/project/directory root, or pass a script
as the `config` argument to `run`:

```scheme
(pipeline
  (frontend "scheme")
  (backend "ir-json")
  (output "generated")
  (transform
    (lambda (file)
      (ir-rewrite-file file
        (lambda (node)
          (if (ir-integer? node)
              (ir-with-integer node (+ (ir-integer node) 2))
              node))))))
```

Options: `frontend`, `backend`, `output`, `source`, `package-name` and `transform`.
Defaults are Scheme → IR JSON, output `dist`, package `user`, and the input directory
as source (project manifests default to `src`). `source` applies to discovery,
not explicit `File` inputs. Output paths are relative to the input/project root.

Precedence is manifest → workspace script → project script → explicit script.
Scalar options override earlier values; transforms accumulate and execute in order.
Each script returns a `pipeline` list of option records. Scripts can define helpers
and use the [Scheme IR bridge](../morphir-scheme/README.md#transform-scripts).
Each transform accepts and returns a typed IR file. During transforms, `source-path`
and `project-root` are strings in the script session.

Every project/run gets a fresh runtime. Within a project, configuration closures
and their state are shared across files in discovery order. Evaluation budgets
apply to each script and each transform; frame allocation is bounded across the
session. A workspace configuration is evaluated separately for each project.

## Frontends and backends

Built-in frontends:

- `scheme`: `.scm` and `.ss`, structural Scheme → current IR.
- `ir-json`: `.json`, versioned IR JSON → current IR using existing migrations.

Built-in backends:

- `ir-json`: current IR JSON, suffix `.ir.json`.
- `scheme`: executable Scheme, suffix `.scm`; requires the Morphir Scheme runtime.

`register_frontend(name, extensions, compile)` accepts `Source -> IRFile`.
`Source` includes path, source-relative path, content, package name and module name.
`register_backend(name, extension, emit)` accepts `IRFile -> String`.
Registrations replace the same name and share the standard transform/diagnostic flow.
All frontends and transforms operate on the current unversioned IR model.

## Host contract and targets

Host paths are portable, relative, slash-separated strings. The engine removes
empty/`.` segments and rejects absolute paths, `..`, backslashes, colons and NUL.
`list(root)` returns recursive file paths relative to the host root, not the list
root. Listed files must remain inside the requested source subtree. `exists` tests
files; `read` returns text. The host must enforce its own filesystem root and symlink
policy. Output directories must be nonempty and cannot contain the source root.

`Host::memory` copies its input map so later caller changes cannot affect a run.
No filesystem/network dependency or Node-only API is imported by this module.
The same API and example build for `native`, `js`, `wasm` and `wasm-gc`.
