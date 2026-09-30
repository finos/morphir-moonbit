import {build} from "esbuild";
import {fileURLToPath} from "node:url";
import {readFile} from "node:fs/promises";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const compilerPath = require.resolve("@moonbit/moonc-worker");
const source = await readFile(compilerPath, "utf8");

await build({entryPoints: [fileURLToPath(new URL("./browser-worker.mjs", import.meta.url))],
  outfile: fileURLToPath(new URL("./dist/browser-worker.js", import.meta.url)),
  // The upstream compiler's optional Node filesystem backend requires constants.
  // Leave that backend external; browser compilation uses its in-memory backend.
  external: ["constants"], bundle: true, platform: "browser", format: "esm", target: "es2022", minify: true,
  logOverride: {"duplicate-case": "silent"},
  plugins: [{name: "isolated-compiler", setup(build) {
    build.onResolve({filter: /^morphir:compiler-factory$/}, () => ({path: "compiler", namespace: "isolated"}));
    build.onLoad({filter: /.*/, namespace: "isolated"}, () => ({contents:
      `export function createCompiler() { const module = {exports:{}}; const exports = module.exports; ${source}\nreturn module.exports; }`,
      loader: "js"}));
  }}]});
