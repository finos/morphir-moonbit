import {Worker} from "node:worker_threads";
import {createRequire} from "node:module";
import {createEmbeddedToolchain, createWorkerToolchain} from "./index.mjs";

const require = createRequire(import.meta.url);
export function createCompiler() {
  // The upstream compiler retains diagnostics globally. Each build needs isolation.
  const path = require.resolve("@moonbit/moonc-worker");
  delete require.cache[path];
  const listeners = new Map(process.eventNames().map(event => [event, new Set(process.listeners(event))]));
  try { return require(path); }
  finally {
    // Compiler initialization installs process-level exception handlers. Embedding
    // must preserve the application's handlers and avoid retaining old compilers.
    for (const event of process.eventNames()) {
      for (const listener of process.listeners(event)) {
        if (!listeners.get(event)?.has(listener)) process.removeListener(event, listener);
      }
    }
  }
}

export function createInProcessToolchain(options) {
  return createEmbeddedToolchain(createCompiler, options);
}

export function createNodeToolchain() {
  return createWorkerToolchain(new Worker(new URL("./node-worker.mjs", import.meta.url),
    {execArgv: []}));
}
