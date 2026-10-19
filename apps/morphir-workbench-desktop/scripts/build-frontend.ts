import { execFileSync } from 'node:child_process';
import { cpSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const desktop = fileURLToPath(new URL('../', import.meta.url));
execFileSync(process.execPath, [fileURLToPath(new URL('./build-icon.ts', import.meta.url)), '--check'], { stdio: 'inherit' });
rmSync(new URL('../frontend/dist/', import.meta.url), { recursive: true, force: true });
execFileSync(process.execPath, [fileURLToPath(new URL('../../morphir-workbench/scripts/build.ts', import.meta.url))], { stdio: 'inherit' });
cpSync(`${desktop}/../morphir-workbench/dist`, `${desktop}/frontend/dist`, { recursive: true });
