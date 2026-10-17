import { buildSync } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const app = fileURLToPath(new URL('../', import.meta.url));
const build = fileURLToPath(new URL('../_build/', import.meta.url));
execFileSync('moon', ['build', '--target', 'js', '--release', '--target-dir', build,
  `${app}browser`, `${app}worker`, `${app}job-host`, `${app}job-core`], { cwd: app, stdio: 'inherit' });
mkdirSync(new URL('../dist/', import.meta.url), { recursive: true });
// The MoonBit output keeps long mangled names, so the bundles are minified. bootstrap.js imports browser.js and
// job-core.js as modules; transport.js starts worker.js as a classic worker, so it stays a script (an IIFE).
const output = name => `${build}/js/release/build/finos/morphir-workbench/${name}/${name}.js`;
for (const [name, format] of [['browser', 'esm'], ['job-core', 'esm'], ['worker', 'iife']]) {
  buildSync({ entryPoints: [output(name)], outfile: `${app}/dist/${name}.js`, format, target: 'es2022', minify: true, legalComments: 'eof' });
}
for (const [source, name] of [
  ['index.html', 'index.html'], ['workbench.css', 'workbench.css'],
  ['browser/model-explorer/explorer.css', 'model-explorer.css'],
  ['browser/bootstrap.js', 'bootstrap.js'], ['browser/transport.js', 'transport.js'],
  ['browser/job-session.js', 'job-session.js'],
  ['browser/job-transport.js', 'job-transport.js'], ['browser/native-session.js', 'native-session.js'],
  ['browser/native-workspace.js', 'native-workspace.js'], ['browser/project-io.js', 'project-io.js'],
]) copyFileSync(`${app}/${source}`, `${app}/dist/${name}`);
buildSync({ entryPoints: [`${app}/browser/editor/code-editor.js`], outfile: `${app}/dist/code-editor.js`, bundle: true, format: 'esm', target: 'es2022', minify: true, legalComments: 'eof' });
buildSync({ entryPoints: [`${app}/browser/artifact-download.js`], outfile: `${app}/dist/artifact-download.js`, bundle: true, format: 'esm', target: 'es2022', minify: true, legalComments: 'eof' });
console.log('Workbench built in apps/morphir-workbench/dist');

for (const name of readdirSync(`${app}/assets`)) {
  if (name.endsWith(".svg")) copyFileSync(`${app}/assets/${name}`, `${app}/dist/${name}`);
}

cpSync(`${app}/assets/samples`, `${app}/dist/samples`, { recursive: true });
