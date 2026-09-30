import {parentPort} from "node:worker_threads";
import {createCompiler} from "./node.mjs";
import {createEmbeddedToolchain, serveToolchain} from "./index.mjs";

serveToolchain(createEmbeddedToolchain(createCompiler), listener => parentPort.on("message", listener),
  result => parentPort.postMessage(result));
