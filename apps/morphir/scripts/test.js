import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync, existsSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const appDirectory = fileURLToPath(new URL("../", import.meta.url));
const workspaceDirectory = fileURLToPath(new URL("../../../", import.meta.url));
const runner = join(workspaceDirectory, "pkgs/morphir-host/runners/wasm.mjs");
const targets = ["native", "js", "wasm", "wasm-gc"];
const selected = process.argv[2] ? [process.argv[2]] : targets;
let reference;

function checkHelp(output) {
  assert.match(output, /^Morphir CLI\r?\n/);
  assert.match(output, /^Usage: morphir <run\|workspace>/m);
}

function exercise(command, prefix, directory, target) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("MORPHIR_")));
  env.HOME = join(directory, "home");
  env.USERPROFILE = env.HOME;
  env.XDG_CONFIG_HOME = join(directory, "config");
  delete env.APPDATA;
  const run = (args, expected = 0, cwd = directory) => {
    const result = spawnSync(command, [...prefix, ...args], {cwd, env, encoding: "utf8"});
    assert.equal(result.status, expected, `${target} ${args.join(" ")}:\n${result.stdout}\n${result.stderr}`);
    return result;
  };
  const put = (path, text) => { mkdirSync(join(directory, path, ".."), {recursive: true}); writeFileSync(join(directory, path), text); };
  put("morphir.toml", '[workspace]\nmembers=["packages/*"]\nexclude=["packages/skip"]\ndefault_member="packages/core"\n');
  put("morphir.config.scm", '(pipeline (transform (lambda (file) file)))');
  put("packages/core/morphir.toml", '[project]\nname="Core"\nsource_directory="src"\n');
  put("packages/tools/morphir.toml", '[project]\nname="Tools"\nsource_directory="lib"\n');
  put("packages/skip/morphir.toml", '[project]\nname="Skip"\n');
  put("packages/core/src/Main.scm", '42');
  put("packages/core/src/nested/Other.scm", '41');
  put("packages/tools/lib/Main.scm", '"hello λ😀"');
  checkHelp(run([]).stdout);
  assert.equal(JSON.parse(run(["workspace", "--json"]).stdout).projects.length, 2);
  const defaultPlan = JSON.parse(run(["run", "--dry-run"]).stdout);
  assert.equal(defaultPlan.sources.length, 2);
  assert.ok(defaultPlan.sources.every(p => p.startsWith("packages/core/")));
  const selectedPlan = JSON.parse(run(["run", "--project", "Tools", "--dry-run"]).stdout);
  assert.deepEqual(selectedPlan.sources, ["packages/tools/lib/Main.scm"]);
  const filePlan = JSON.parse(run(["run", "packages/core/src/Main.scm", "--dry-run"]).stdout);
  assert.deepEqual(filePlan.sources, ["packages/core/src/Main.scm"]);
  const dirPlan = JSON.parse(run(["run", "packages/core/src/nested", "--dry-run"]).stdout);
  assert.deepEqual(dirPlan.sources, ["packages/core/src/nested/Other.scm"]);
  // WASI can only discover ancestors within its preopened development root.
  if (target !== "wasm") {
    assert.deepEqual(JSON.parse(run(["run", "--dry-run"], 0, join(directory, "packages/tools")).stdout).sources,
      ["packages/tools/lib/Main.scm"]);
  }
  const result = JSON.parse(run(["run", "--all", "--json"]).stdout);
  assert.equal(result.processed, 3);
  assert.equal(result.committed.length, 2);
  const artifact = join(directory, ".morphir/out/packages/core/compile.dest/Main.ir.json");
  const before = readFileSync(artifact, "utf8");
  if (reference) assert.deepEqual(JSON.parse(before), reference);
  else reference = JSON.parse(before);
  // Rerun replaces owned task directories and removes stale task outputs.
  put(".morphir/out/packages/core/compile.dest/stale", "old");
  run(["run", "--all"]);
  assert.ok(!existsSync(join(directory, ".morphir/out/packages/core/compile.dest/stale")));
  put("packages/tools/morphir.config.scm", '(pipeline (transform (lambda (file) 123)))');
  const failure = JSON.parse(run(["run", "--all", "--json"], 1).stdout);
  assert.equal(failure.successful, false);
  assert.deepEqual(failure.committed, []);
  assert.equal(readFileSync(artifact, "utf8"), before);
  rmSync(join(directory, "packages/tools/morphir.config.scm"));
  put("morphir.yaml", "workspace: {}");
  assert.match(run(["run"], 2).stderr, /Ambiguous/);
  rmSync(join(directory, "morphir.yaml"));
  run(["run", "--all", "--project", "Core"], 2);
  run(["run", "--output", "../outside"], 2);
  // A busy publisher fails without changing the previous outputs.
  mkdirSync(join(directory, ".morphir/out/.morphir-publish.lock"));
  run(["run"], 1);
  rmSync(join(directory, ".morphir/out/.morphir-publish.lock"), {recursive:true});
  assert.equal(readFileSync(artifact, "utf8"), before);
  if (process.platform !== "win32") {
    symlinkSync("Main.scm", join(directory, "packages/core/src/alias.scm"));
    assert.match(run(["run"], 2).stderr, /link/);
    rmSync(join(directory, "packages/core/src/alias.scm"));
  }
  writeFileSync(join(directory,"packages/core/src/Invalid.scm"), Buffer.from([0xff]));
  assert.equal(JSON.parse(run(["run","packages/core/src/Invalid.scm","--json"],1).stdout).successful,false);
  rmSync(join(directory,"packages/core/src/Invalid.scm"));
  // Legacy manifests still pass through the new CLI.
  const legacy = join(directory, "legacy");
  put("legacy/morphir.json", '{"name":"Legacy","sourceDirectory":"src"}');
  put("legacy/src/main.scm", '42');
  // Keep the legacy project independent of its enclosing test workspace.
  run(["run", "--dry-run"], 0, legacy);
  console.log(`CLI workspace integration passed: ${target}`);
}

for (const target of selected) {
  assert.ok(targets.includes(target), `Unknown target: ${target}`);
  execFileSync("moon", ["build", "--target", target, "--release"], {cwd: appDirectory, stdio:"inherit"});
  const artifactDirectory = join(workspaceDirectory, "_build", target, "release/build/morphir/morphir");
  const directory = mkdtempSync(join(tmpdir(), "morphir-cli-"));
  try {
    if (target === "native") exercise(join(artifactDirectory,"morphir.exe"), [], directory, target);
    else if (target === "js") exercise(process.execPath, [join(artifactDirectory,"morphir.js")], directory, target);
    else {
      const artifact = join(artifactDirectory,"morphir.wasm");
      if (target === "wasm") {
        const module = await WebAssembly.compile(readFileSync(artifact));
        assert.ok(WebAssembly.Module.imports(module).every(i => i.module === "wasi_snapshot_preview1"));
      }
      exercise(process.execPath, [runner,artifact], directory, target);
    }
  } finally { rmSync(directory, {recursive:true,force:true}); }
}

if (selected.includes("js")) {
  assert.ok(process.env.npm_execpath, "Run this script with npm test");
  const directory = mkdtempSync(join(tmpdir(), "morphir-npm-"));
  const npm = (args, cwd) => execFileSync(process.execPath,
    [process.env.npm_execpath,"--cache",join(directory,"cache"),...args], {cwd,encoding:"utf8"});
  try {
    npm(["pack","--pack-destination",directory], appDirectory);
    const tarball = readdirSync(directory).find(p => p.endsWith(".tgz"));
    assert.ok(tarball);
    npm(["install","--prefix",directory,"--ignore-scripts","--no-audit","--no-fund","--offline",join(directory,tarball)],directory);
    checkHelp(npm(["exec","--prefix",directory,"--offline","--","morphir","--help"], directory));
    const installed = join(directory,"node_modules/@morphir/morphir/bin/morphir.js");
    const fixture = join(directory,"fixture");
    mkdirSync(fixture);
    exercise(process.execPath,[installed],fixture,"npm");
    console.log("Installed npm package integration passed");
  } finally { rmSync(directory,{recursive:true,force:true}); }
}
