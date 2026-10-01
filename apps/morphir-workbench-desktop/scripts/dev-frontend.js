const { execFileSync, spawn } = require('node:child_process');
const { resolve } = require('node:path');

const workbench = resolve(__dirname, '../../morphir-workbench');
execFileSync(process.execPath, [resolve(workbench, 'scripts/build.js')], { stdio: 'inherit' });
const server = spawn(process.execPath, [resolve(workbench, 'scripts/serve.js')], { stdio: 'inherit' });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.kill(signal));
server.on('exit', code => process.exit(code ?? 1));
