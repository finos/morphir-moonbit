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
  assert.match(output, /^Usage: morphir/m);
  assert.match(output, /project/);
  assert.match(output, /toolchain/);
  assert.match(output, /--json-lines/);
}

function exercise(command, prefix, directory, target, buildHelper = join(appDirectory,"build-provider/library-build.mjs")) {
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
  assert.deepEqual(JSON.parse(run(["--help", "--json"]).stdout).commands, ["run", "execute", "verify", "conform", "workspace", "project list", "toolchain info", "toolchain setup", "toolchain build", "toolchain run", "toolchain exec"]);
  assert.equal(lines(["--help"])[0].type, "help");
  for (const args of [["run", "--help"], ["workspace", "--help"], ["project", "list", "--help"]]) {
    assert.ok(JSON.parse(run([...args, "--json"]).stdout).options.includes("--json-lines"));
    assert.equal(lines(args)[0].type, "help");
  }
  assert.equal(lines(["unknown"], 2)[0].type, "error");
  assert.match(JSON.parse(run(["--json", "toolchain", "run", "--help"]).stdout).usage, /^Usage: morphir toolchain run/m);
  assert.match(JSON.parse(run(["run", "--targte", "js", "--json"], 2).stdout).error, /--target/);
  assert.match(JSON.parse(run(["toolchain", "build", "--yes", "--json"], 2).stdout).error, /--yes/);
  assert.match(JSON.parse(run(["verify", "missing", "--suite=one", "--suite", "two", "--json"], 2).stdout).error, /Repeated option: --suite/);

  for (const args of [["run", "--help", "--unknown"], ["run", "--morphir-internal-help"],
    ["run", "--json=true"], ["run", "--target", "--help"],
    ["toolchain", "info", "--timeout", "1", "--timeout", "2"]]) {
    const error = JSON.parse(run([...args, "--json"], 2).stdout);
    assert.equal(error.successful, false);
    assert.equal(typeof error.error, "string");
    assert.equal(lines(args, 2)[0].type, "error");
  }
  assert.equal(lines(["workspace", "--json"], 2)[0].type, "error");
  const tooling = JSON.parse(run(["toolchain", "info", "--json"]).stdout);
  if (target === "wasm") {
    assert.equal(tooling.supported, false);
    assert.equal(lines(["toolchain", "setup", "--yes"], 2)[0].type, "error");
  } else {
    assert.equal(tooling.validated, true);
    assert.equal(lines(["toolchain", "info"])[0].type, "toolchain");
    const toolhome = tooling.home;
    put("moon-example/moon.mod", 'name="morphir/tooling-example"\nversion="0.0.0"\n');
    put("moon-example/moon.pkg", 'pkgtype(kind: "executable")\nimport {"moonbitlang/core/env"}\n');
    put("moon-example/main.mbt", 'fn main { for arg in @env.args()[1:] { println(arg) } }\n');
    const built = JSON.parse(run(["toolchain", "build", "moon-example", "--home", toolhome, "--target", "wasm", "--json"]).stdout);
    assert.equal(built.successful, true);
    const executed = JSON.parse(run(["toolchain", "run", "moon-example", "--home", toolhome, "--json", "--", "--help", "--json", "", "λ value", "--", "$(echo forbidden)"]).stdout);
    assert.equal(executed.process.stdout.trim(), '--help\n--json\n\nλ value\n--\n$(echo forbidden)');
    assert.equal(executed.successful, true);
    if (tooling.moonx) {
      put("tooling.mbtx", 'fn main { println(42) }\n');
      const script=JSON.parse(run(["toolchain","exec","tooling.mbtx","--home",toolhome,"--json"]).stdout);
      assert.equal(script.process.stdout.trim(),'42');
    }
    assert.equal(lines(["toolchain", "setup", "--home", toolhome])[0].data.validated, true);
    const invalid = JSON.parse(run(["toolchain", "info", "--home", "absent", "--json"],2).stdout);
    assert.match(invalid.error, /Missing moon/);
    put("moon-example/main.mbt", 'fn main { let n : Int = "bad"; println(n) }\n');
    const failed = JSON.parse(run(["toolchain", "build", "moon-example", "--home", toolhome, "--json"],255).stdout);
    assert.equal(failed.successful,false);
    assert.match(failed.process.stderr, /Mismatch/);
  }
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
  // Checkpoints use the same source selection and private publication lifecycle.
  // No toolchain home is configured, and generation does not invoke acquisition.
  put("checkpoints/morphir.toml", '[project]\nname="Pricing"\n[frontend]\nlanguage="ir-json"\n[pipeline]\nbackend="checkpoint"\n');
  put("checkpoints/src/Main.json", '{"formatVersion":3,"distribution":["Library",[["pricing"]],[],{"modules":[]}]}');
  const checkpointArgs = ["run", "checkpoints"];
  const checkpointPlan = JSON.parse(run([...checkpointArgs, "--dry-run", "--json"]).stdout);
  assert.deepEqual(checkpointPlan.sources, ["src/Main.json"]);
  assert.equal(checkpointPlan.boundaries[0].inputFormat, "morphir-json");
  assert.equal(checkpointPlan.boundaries[0].outputFormat, "ion-binary");
  assert.equal(checkpointPlan.boundaries[0].profile, "morphir-pipeline-v1");
  assert.equal(checkpointPlan.boundaries[0].readBytes, false);
  assert.equal(checkpointPlan.boundaries[0].writeBytes, true);
  assert.ok(!existsSync(join(directory, "checkpoints/.morphir/out")));
  const binaryResult = JSON.parse(run([...checkpointArgs, "--json"]).stdout);
  assert.equal(binaryResult.successful, true);
  assert.equal(binaryResult.artifactDetails[0].encoding, "binary");
  assert.equal(binaryResult.artifactDetails[0].status, "accepted");
  assert.equal(binaryResult.committed.length, 1);
  const checkpointRoot = join(directory, "checkpoints/.morphir/out/compile.dest");
  const binary = readFileSync(join(checkpointRoot, "Main.ionb"));
  assert.deepEqual([...binary.subarray(0,4)], [0xe0, 0x01, 0x00, 0xea]);
  // Read the real binary file without interpreting it as UTF-8.
  put("checkpoints/src/Main.ionb", binary);
  rmSync(join(directory, "checkpoints/src/Main.json"));
  const textResult = JSON.parse(run([...checkpointArgs, "--frontend", "ion-binary", "--backend", "checkpoint", "--checkpoint-format", "ion-text", "--json"]).stdout);
  assert.equal(textResult.boundaries[0].readBytes, true);
  assert.equal(textResult.boundaries[0].writeBytes, false);
  assert.equal(textResult.artifactDetails[0].encoding, "text");
  const ionText = readFileSync(join(checkpointRoot, "Main.ion"), "utf8");
  assert.match(ionText, /morphir_pipeline::/);
  assert.match(ionText, /formatVersion: 4/);
  assert.ok(!existsSync(join(checkpointRoot, "Main.ionb")));
  put("checkpoints/src/Main.ion", ionText);
  rmSync(join(directory, "checkpoints/src/Main.ionb"));
  const checkpointRecords = lines([...checkpointArgs, "--frontend", "ion-text"]);
  assert.equal(checkpointRecords.find(r => r.type === "boundary").data.inputFormat, "ion-text");
  assert.equal(checkpointRecords.find(r => r.type === "accepted").data.format, "ion-binary");
  assert.equal(checkpointRecords.filter(r => r.type === "committed").length, 1);
  assert.deepEqual(readFileSync(join(checkpointRoot, "Main.ionb")), binary);
  const humanCheckpoint = run([...checkpointArgs, "--frontend", "ion-text"]).stdout;
  assert.match(humanCheckpoint, /ion-text -> ion-binary/);
  assert.match(humanCheckpoint, /Accepted .*Main\.ionb/);
  assert.match(humanCheckpoint, /Published .*compile\.dest/);
  // JSON remains a supported explicit export format.
  const jsonCheckpoint = JSON.parse(run([...checkpointArgs, "--frontend", "ion-text", "--checkpoint-format", "morphir-json", "--json"]).stdout);
  assert.equal(jsonCheckpoint.artifactDetails[0].format, "morphir-json");
  assert.equal(JSON.parse(readFileSync(join(checkpointRoot,"Main.json"),"utf8")).formatVersion,4);
  // Rich annotations remain intact through real text/binary files.
  const richIon = ionText.replace("morphir_pipeline::", "morphir_pipeline::audit::")
    .replace("metadata: []", 'metadata: [{node_id:"node:1",data:tag::tag::unknown::{price:12.340d0,blob:{{/wCA}},nothing:null.int}}]');
  put("checkpoints/src/Main.ion", richIon);
  run([...checkpointArgs,"--frontend","ion-text"]);
  const richBinary = readFileSync(join(checkpointRoot,"Main.ionb"));
  put("checkpoints/src/Main.ionb",richBinary);
  rmSync(join(directory,"checkpoints/src/Main.ion"));
  run([...checkpointArgs,"--frontend","ion-binary","--checkpoint-format","ion-text"]);
  const richText = readFileSync(join(checkpointRoot,"Main.ion"),"utf8");
  assert.match(richText,/morphir_pipeline::audit::/);
  assert.match(richText,/tag::tag::unknown::/);
  assert.match(richText,/price: 12\.340(?:d0)?,/);
  assert.match(richText,/null.int/);
  const lossy = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--checkpoint-format","morphir-json","--json"],1).stdout);
  assert.equal(lossy.successful,false);
  assert.deepEqual(lossy.committed,[]);
  assert.match(lossy.diagnostics[0].message,/data.lossy_conversion/);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  put("checkpoints/src/Main.ionb",Buffer.from([0xe0,0x01,0x00,0xea,0xff]));
  const malformed = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--json"],1).stdout);
  assert.equal(malformed.successful,false);
  assert.deepEqual(malformed.committed,[]);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  put("checkpoints/src/Main.ionb",richBinary);
  put("checkpoints/src/Main.10n",richBinary);
  assert.match(run([...checkpointArgs,"--frontend","ion-binary","--dry-run"],2).stderr,/Duplicate output path/);
  rmSync(join(directory,"checkpoints/src/Main.10n"));
  // A held publisher lock prevents binary replacement and preserves previous files.
  mkdirSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock"));
  const busy = JSON.parse(run([...checkpointArgs,"--frontend","ion-binary","--json"],1).stdout);
  assert.equal(busy.artifactDetails.length,1);
  assert.deepEqual(busy.committed,[]);
  assert.ok(busy.publicationError);
  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  rmSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock"),{recursive:true});
  assert.match(run([...checkpointArgs,"--checkpoint-format","bogus"],2).stderr,/data.unknown_codec/);
  // A file/directory collision is rejected during planning, preserving the old task.
  const simpleJson = '{"formatVersion":3,"distribution":["Library",[["pricing"]],[],{"modules":[]}]}';
  put("checkpoints/src/Main.json",simpleJson);
  rmSync(join(directory,"checkpoints/src/Main.ionb"));
  put("checkpoints/src/Main.ionb/Nested.json",simpleJson);
  const stagingFailure = JSON.parse(run([...checkpointArgs,"--frontend","ir-json","--json"],2).stdout);
  assert.match(stagingFailure.error,/Duplicate output path/);
  assert.deepEqual(stagingFailure.committed,[]);

  assert.equal(readFileSync(join(checkpointRoot,"Main.ion"),"utf8"),richText);
  assert.ok(!existsSync(join(directory,"checkpoints/.morphir/out/.morphir-publish.lock")));

  // Complete library generation uses the same byte, component and publication lifecycle.
  put("libraries/morphir.toml", "[project]\nname='Pricing'\n[frontend]\nlanguage='ir-json'\n[pipeline]\nbackend='moonbit'\nvalidation='source-only'\n");
  put("libraries/src/Main.json",simpleJson);
  const libraryArgs=["run","libraries","--backend","moonbit","--validation","source-only","--component","json-identity"];
  const libraryPlan=JSON.parse(run([...libraryArgs,"--dry-run","--json"]).stdout);
  assert.equal(libraryPlan.components[0].transport,"morphir-json");
  assert.equal(libraryPlan.boundaries[0].outputFormat,"moonbit");
  const library=JSON.parse(run([...libraryArgs,"--json"]).stdout);
  assert.equal(library.successful,true);assert.equal(library.projects.length,1);assert.equal(library.artifacts.length,4);
  assert.equal(library.validated.length,0);assert.equal(library.publicationDetails[0].status,"published");
  const libraryRoot=join(directory,"libraries/.morphir/out/compile.dest/Main");
  assert.deepEqual(readdirSync(libraryRoot).sort(),["library.mbt","moon.mod","moon.pkg","symbols.10n"]);
  put("libraries/.morphir/out/compile.dest/Main/stale.mbt","stale");
  put("libraries/.morphir/out/compile.dest/Main/build-receipt.ionb","stale receipt");
  const libraryLines=lines(libraryArgs);
  assert.equal(libraryLines.filter(r=>r.type==="generated").length,1);
  assert.equal(libraryLines.filter(r=>r.type==="validated").length,0);
  assert.equal(libraryLines.filter(r=>r.type==="published").length,1);
  assert.ok(!existsSync(join(libraryRoot,"stale.mbt")));assert.ok(!existsSync(join(libraryRoot,"build-receipt.ionb")));
  const libraryBefore=readFileSync(join(libraryRoot,"symbols.10n"));
  put("libraries/src/Bad.json","malformed");
  const failedLibrary=JSON.parse(run([...libraryArgs,"--json"],1).stdout);
  assert.equal(failedLibrary.successful,false);assert.deepEqual(failedLibrary.committed,[]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),libraryBefore);
  rmSync(join(directory,"libraries/src/Bad.json"));
  // Current JSON and historical JSON both enter Ion checkpoints and buildable source.
  const checkpointLibrary=["run","libraries","--backend","checkpoint","--checkpoint-format","ion-text"];
  run(checkpointLibrary);
  const libraryIonPath=join(directory,"libraries/.morphir/out/compile.dest/Main.ion");
  const libraryIon=readFileSync(libraryIonPath,"utf8").replace("metadata: []",'metadata: [{node_id:"unit:Main",data:tag::tag::{amount:12.340d0,blob:{{/wCA}},nil:null.int}}]');
  put("libraries/src/Main.ion",libraryIon);rmSync(join(directory,"libraries/src/Main.json"));
  run([...libraryArgs,"--frontend","ion-text"]);
  const richSymbols=readFileSync(join(libraryRoot,"symbols.10n"));
  run([...checkpointLibrary,"--frontend","ion-text","--checkpoint-format","ion-binary"]);
  put("libraries/src/Main.ionb",readFileSync(join(directory,"libraries/.morphir/out/compile.dest/Main.ionb")));
  rmSync(join(directory,"libraries/src/Main.ion"));
  run([...libraryArgs,"--frontend","ion-binary"]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),richSymbols);
  const required=[...libraryArgs,"--frontend","ion-binary","--validation","required"];
  const unsupported=JSON.parse(run([...required,"--json"],1).stdout);
  assert.match(unsupported.publicationError,/build.provider_required/);assert.deepEqual(unsupported.committed,[]);
  assert.deepEqual(readFileSync(join(libraryRoot,"symbols.10n")),richSymbols);
  if(target!=="wasm") {
    const provider=["--build-provider","process","--build-helper",buildHelper,"--build-node",process.execPath,"--home",tooling.home,"--sdk",join(workspaceDirectory,"pkgs/morphir-sdk"),"--target","wasm"];
    const builtLibrary=JSON.parse(run([...required,...provider,"--json"]).stdout);
    assert.equal(builtLibrary.successful,true);assert.equal(builtLibrary.validated.length,1);
    assert.equal(builtLibrary.artifacts.length,5);assert.ok(existsSync(join(libraryRoot,"build-receipt.ionb")));
    const builtBefore=readFileSync(join(libraryRoot,"build-receipt.ionb"));
    const compilerFailure=JSON.parse(run([...required,...provider,"--sdk",join(directory,"absent-sdk"),"--json"],1).stdout);
    assert.equal(compilerFailure.successful,false);assert.deepEqual(compilerFailure.committed,[]);
    assert.deepEqual(readFileSync(join(libraryRoot,"build-receipt.ionb")),builtBefore);
    const timedOut=JSON.parse(run([...required,...provider,"--timeout","20","--json"],1).stdout);
    assert.equal(timedOut.successful,false);assert.deepEqual(timedOut.committed,[]);
    assert.deepEqual(readFileSync(join(libraryRoot,"build-receipt.ionb")),builtBefore);
    run([...libraryArgs,"--frontend","ion-binary"]);
    assert.ok(!existsSync(join(libraryRoot,"build-receipt.ionb")));
  }

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
    assert.ok(existsSync(join(directory,"node_modules/@morphir/morphir/build-provider/library-build.mjs")));
    const installed = join(directory,"node_modules/@morphir/morphir/bin/morphir.js");
    const fixture = join(directory,"fixture");
    mkdirSync(fixture);
    exercise(process.execPath,[installed],fixture,"npm",join(directory,"node_modules/@morphir/morphir/build-provider/library-build.mjs"));
    console.log("Installed npm package integration passed");
  } finally { rmSync(directory,{recursive:true,force:true}); }
}
