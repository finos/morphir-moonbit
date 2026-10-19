#!/usr/bin/env node

import { terminalWorker } from '../../../pkgs/morphir-host/runners/terminal-worker.mts';

if (!terminalWorker(new URL(import.meta.url), process.argv.slice(2))) {
  await import('../dist/morphir.js');
}
