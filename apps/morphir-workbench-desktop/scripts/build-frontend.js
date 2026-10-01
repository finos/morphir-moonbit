const { execFileSync } = require('node:child_process');
const { cpSync } = require('node:fs');
const { resolve } = require('node:path');

const desktop = resolve(__dirname, '..');
execFileSync(process.execPath, [resolve(desktop, '../morphir-workbench/scripts/build.js')], { stdio: 'inherit' });
cpSync(resolve(desktop, '../morphir-workbench/dist'), resolve(desktop, 'frontend/dist'), { recursive: true });
