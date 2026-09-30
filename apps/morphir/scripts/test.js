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
  assert.match(output, /morphir project list/);
  assert.match(output, /--json-lines/);
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
  const lines = (args, expected = 0) => run([...args, "--json-lines"], expected).stdout.trim().split(/\r?\n/).map(line => {
    const record = JSON.parse(line);
    assert.equal(typeof record.type, "string");
    assert.ok(Object.hasOwn(record, "data"));
    return record;
  });
  put("morphir.toml", '[workspace]\nmembers=["packages/*"]\nexclude=["packages/skip"]\ndefault_member="packages/core"\n');
  put("morphir.config.scm", '(pipeline (transform (lambda (file) file)))');
  put("packages/core/morphir.toml", '[project]\nname="Core"\nsource_directory="src"\n');
  put("packages/tools/morphir.toml", '[project]\nname="Tools"\nsource_directory="lib"\n');
  put("packages/skip/morphir.toml", '[project]\nname="Skip"\n');
  put("packages/core/src/Main.scm", '42');
  put("packages/core/src/nested/Other.scm", '41');
  put("packages/tools/lib/Main.scm", '"hello λ😀"');
  checkHelp(run([]).stdout);
  assert.deepEqual(JSON.parse(run(["--help", "--json"]).stdout).commands, ["run", "workspace", "project list"]);
  assert.equal(lines(["--help"])[0].type, "help");
  for (const args of [["run", "--help"], ["workspace", "--help"], ["project", "list", "--help"]]) {
    assert.ok(JSON.parse(run([...args, "--json"]).stdout).options.includes("--json-lines"));
    assert.equal(lines(args)[0].type, "help");
  }
  assert.equal(lines(["unknown"], 2)[0].type, "error");
  assert.equal(lines(["workspace", "--json"], 2)[0].type, "error");
  assert.equal(JSON.parse(run(["workspace", "--json"]).stdout).projects.length, 2);
  const workspaceLines = lines(["workspace"]);
  assert.equal(workspaceLines[0].type, "workspace");
  assert.equal(workspaceLines.filter(r => r.type === "project").length, 2);
  const defaultProjects = JSON.parse(run(["project", "list", "--json"]).stdout).projects;
  assert.deepEqual(defaultProjects.map(p => [p.name, p.frontend, p.target]),
    [["Core", "scheme", "ir-json"], ["Tools", "scheme", "ir-json"]]);
  assert.match(run(["project", "list"]).stdout, /^NAME\tPATH\tFRONTEND\tTARGET/m);
  const dryLines = lines(["run", "--dry-run"]);
  assert.equal(dryLines.filter(r => r.type === "source").length, 2);
  assert.equal(dryLines.at(-1).type, "plan");
  assert.equal(dryLines.at(-1).data.sourceCount, 2);
  assert.ok(!existsSync(join(directory, ".morphir/out")));
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
  const failureLines = lines(["run", "--all"], 1);
  assert.ok(failureLines.some(r => r.type === "diagnostic"));
  assert.equal(failureLines.at(-1).data.successful, false);
  assert.equal(failureLines.filter(r => r.type === "committed").length, 0);
  rmSync(join(directory, "packages/tools/morphir.config.scm"));
  const streamed = lines(["run", "--all"]);
  assert.equal(streamed.filter(r => r.type === "artifact").length, 3);
  assert.equal(streamed.filter(r => r.type === "committed").length, 2);
  assert.equal(streamed.at(-1).type, "result");
  assert.equal(streamed.at(-1).data.successful, true);
  assert.equal(streamed.at(-1).data.processed, 3);
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
  if (target !== "wasm") {
    // An explicit Morphir home works without OS home/config variables.
    put("config-home/morphir.toml", '[frontend]\nlanguage="missing-from-registry"');
    const saved = {...env};
    for (const key of ["HOME","USERPROFILE","APPDATA","XDG_CONFIG_HOME"]) delete env[key];
    env.MORPHIR_HOME = join(directory,"config-home");
    assert.match(run(["run","--dry-run"],2).stderr,/Unknown frontend: missing-from-registry/);
    delete env.MORPHIR_HOME;
    Object.assign(env,saved);
    rmSync(join(directory,"config-home"),{recursive:true});
  }
  // Listing resolves layered languages without requiring their compiler plugins.
  put("catalog/morphir.toml", '[workspace]\nmembers=["a","b","c"]\n[frontend]\nlanguage="elm"\n[pipeline]\nbackend="scala"\n');
  put("catalog/a/morphir.toml", '[project]\nname="A"\n');
  put("catalog/b/morphir.toml", '[project]\nname="B"\n[frontend]\nlanguage="scheme"\n[pipeline]\nbackend="ir-json"\n');
  put("catalog/c/morphir.toml", '[project]\nname="C"\n[frontend]\nlanguage="moonbit"\n[pipeline]\nbackend="javascript"\n');
  put("catalog/morphir.config.scm", '(pipeline (transform (lambda (file) file)))');
  put("catalog/b/morphir.config.scm", '(pipeline (backend "scheme"))');
  writeFileSync(join(directory, "catalog/a/Invalid.elm"), Buffer.from([0xff]));
  const list = (...filters) => JSON.parse(run(["project", "list", "catalog", ...filters, "--json"]).stdout);
  assert.deepEqual(list().projects.map(p => [p.name, p.frontend, p.target]),
    [["A", "elm", "scala"], ["B", "scheme", "scheme"], ["C", "moonbit", "javascript"]]);
  assert.deepEqual(list("--frontend", "elm").projects.map(p => p.name), ["A"]);
  assert.deepEqual(list("--target", "scheme").projects.map(p => p.name), ["B"]);
  assert.deepEqual(list("--frontend", "elm", "--frontend", "scheme").projects.map(p => p.name), ["A", "B"]);
  assert.deepEqual(list("--target", "scala", "--target", "javascript").projects.map(p => p.name), ["A", "C"]);
  assert.deepEqual(list("--frontend", "scheme", "--target", "scheme").projects.map(p => p.name), ["B"]);
  assert.deepEqual(list("--frontend", "scheme", "--target", "scala").projects, []);
  assert.deepEqual(list("--frontend", "missing").projects, []);
  assert.ok(!existsSync(join(directory, "catalog/.morphir/out")));
  assert.deepEqual(lines(["project", "list", "catalog", "--target", "scheme"]).map(r => r.type), ["project", "result"]);
  const emptyList = lines(["project", "list", "catalog", "--frontend", "missing"]);
  assert.equal(emptyList.length, 1);
  assert.equal(emptyList[0].data.projectCount, 0);
  for (const args of [["project"], ["project", "bad"], ["project", "list", "--target"],
      ["project", "list", "--frontend", ""], ["project", "list", "--all"]]) {
    assert.equal(lines(args, 2)[0].type, "error");
    assert.equal(JSON.parse(run([...args, "--json"], 2).stdout).successful, false);
  }
  put("select.scm", '(pipeline (backend "rust"))');
  assert.equal(list("--config", "select.scm", "--target", "rust").projects.length, 3);
  put("catalog/b/morphir.config.scm", '(pipeline (frontend 42))');
  const invalidList = JSON.parse(run(["project", "list", "catalog", "--frontend", "elm", "--json"], 2).stdout);
  assert.deepEqual(invalidList.projects.map(p => p.name), ["A"]);
  assert.equal(invalidList.successful, false);
  assert.equal(invalidList.diagnostics.length, 1);
  const invalidLines = lines(["project", "list", "catalog", "--frontend", "missing"], 2);
  assert.deepEqual(invalidLines.map(r => r.type), ["diagnostic", "result"]);
  assert.equal(invalidLines.at(-1).data.successful, false);
  put("catalog/b/morphir.config.scm", '(pipeline (backend "scheme"))');
  put("catalog/b/morphir.toml", '[project]\nname="B"\n[ir]\nformat_version=5\n');
  const invalidIr = JSON.parse(run(["project", "list", "catalog", "--json"], 2).stdout);
  assert.equal(invalidIr.successful, false);
  assert.match(invalidIr.diagnostics[0].message, /versions are integers 1 through 4/);
  assert.equal(lines(["project", "list", "catalog"], 2).at(-1).data.successful, false);
  // Legacy manifests still pass through the new CLI.
  const legacy = join(directory, "legacy");
  put("legacy/morphir.json", '{"name":"Legacy","sourceDirectory":"src"}');
  put("legacy/src/main.scm", '42');
  // Keep the legacy project independent of its enclosing test workspace.
  run(["run", "--dry-run"], 0, legacy);
  assert.equal(JSON.parse(run(["project", "list", "--json"], 0, legacy).stdout).projects[0].name, "Legacy");
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
