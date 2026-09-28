import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const appDirectory = fileURLToPath(new URL("../", import.meta.url));
const workspaceDirectory = fileURLToPath(new URL("../../../", import.meta.url));
const targets = ["native", "js", "wasm", "wasm-gc"];
const selected = process.argv[2] ? [process.argv[2]] : targets;

function checkOutput(output) {
  assert.match(output, /^Morphir CLI\r?\n/);
  assert.match(output, /^Usage: morphir$/m);
}

for (const target of selected) {
  assert.ok(targets.includes(target), `Unknown target: ${target}`);
  const output = execFileSync(
    "moon",
    ["run", ".", "--target", target, "--release"],
    { cwd: appDirectory, encoding: "utf8" },
  );
  checkOutput(output);
  console.log(`CLI smoke test passed: ${target}`);

  const artifactDirectory = join(
    workspaceDirectory, "_build", target, "release/build/morphir/morphir",
  );
  if (target === "native") {
    checkOutput(execFileSync(join(artifactDirectory, "morphir.exe"), [], {
      cwd: tmpdir(), encoding: "utf8",
    }));
    console.log("CLI smoke test passed: standalone native executable");
  } else if (target === "wasm") {
    // Run under a WASI host with no MoonBit-specific imports.
    checkOutput(execFileSync(process.execPath, [
      "--input-type=module", "--eval",
      `import { readFileSync } from "node:fs";
       import { WASI } from "node:wasi";
       const wasi = new WASI({ version: "preview1" });
       const module = await WebAssembly.compile(readFileSync(process.argv[1]));
       const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
       wasi.start(instance);`,
      join(artifactDirectory, "morphir.wasm"),
    ], { cwd: tmpdir(), encoding: "utf8" }));
    console.log("CLI smoke test passed: standalone WASI module");
  }
}

if (selected.includes("js")) {
  // npm sets this path when running `npm test`. Calling it through Node also
  // works on Windows, where npm.cmd cannot be executed without a shell.
  assert.ok(process.env.npm_execpath, "Run this script with npm test");
  const directory = mkdtempSync(join(tmpdir(), "morphir-cli-"));
  const npm = (args, cwd) => execFileSync(
    process.execPath,
    [process.env.npm_execpath, "--cache", join(directory, "cache"), ...args],
    { cwd, encoding: "utf8" },
  );
  try {
    // Exercise prepack, then install the tarball into an unrelated directory.
    npm(["pack", "--pack-destination", directory], appDirectory);
    const tarballs = readdirSync(directory).filter((name) => name.endsWith(".tgz"));
    assert.equal(tarballs.length, 1);
    npm([
      "install", "--prefix", directory, "--ignore-scripts", "--no-audit",
      "--no-fund", "--offline", join(directory, tarballs[0]),
    ], directory);
    const output = npm([
      "exec", "--prefix", directory, "--offline", "--", "morphir",
    ], directory);
    checkOutput(output);
    console.log("CLI smoke test passed: installed npm package");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
