import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {compilerIdentity, stableVersion} from '../build-provider/capabilities.mjs';
import {excluded, hash, treeIdentity} from '../build-provider/identity.mjs';
import {includeDependencyPath} from '../build-provider/paths.mjs';

const repository = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.MOON_HOME, 'Set MOON_HOME to the pinned compiler/core installation');
const home = resolve(process.env.MOON_HOME);
const moon = join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const moonc = join(home, 'bin', process.platform === 'win32' ? 'moonc.exe' : 'moonc');
const env = {...process.env, MOON_HOME: home, MOONBIT_NEW_NATIVE: '0', PATH: join(home, 'bin') + delimiter + process.env.PATH};
delete env.MOON_WORK;
assert.ok(execFileSync(moonc, ['-v'], {encoding: 'utf8', env}).trim().startsWith('v' + stableVersion));
assert.match(readFileSync(join(home, 'lib/core/moon.mod'), 'utf8'), /version\s*=\s*"0\.10\.14\+7d59c7ec9"/);
const sdk = resolve(process.env.MORPHIR_FRONTEND_SDK || join(repository, 'pkgs/morphir-sdk'));
assert.match(readFileSync(join(sdk, 'moon.mod'), 'utf8'), /name\s*=\s*"finos\/morphir-sdk"/);
assert.match(readFileSync(join(sdk, 'moon.mod'), 'utf8'), /version\s*=\s*"0\.1\.0"/);
const semanticPin = JSON.parse(readFileSync(join(sdk, 'conformance/bindings.json'), 'utf8')).pin;
assert.equal(semanticPin, 'bc99af69a8b24d391311fae3822a87eafef3c334');
const receipts = resolve(repository, process.env.MORPHIR_FRONTEND_RECEIPTS || '.dev/frontend-acceptance');
mkdirSync(receipts, {recursive: true});
rmSync(join(receipts, 'identity.json'), {force: true});
const workspace = mkdtempSync(join(tmpdir(), 'morphir-frontend-'));
const lanes = [];
try {
  const output = JSON.parse(execFileSync(moon, ['run', 'pkgs/morphir-moonbit-frontend/acceptance', '--target', 'native'], {
    cwd: repository, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216,
  }));
  assert.equal(output.profile, 'moonbit-model-bool-v1');
  assert.equal(output.parserVersion, '0.4.1');
  assert.equal(output.models.length, 11);
  assert.equal(new Set(output.models.map(m => m.id)).size, 11);
  writeFileSync(join(receipts, 'models.json'), JSON.stringify(output, null, 2) + '\n');
  const sdkIdentity = treeIdentity(sdk);
  cpSync(sdk, join(workspace, 'sdk'), {recursive: true, filter: path => includeDependencyPath(sdk, path, excluded)});
  assert.equal(treeIdentity(join(workspace, 'sdk')), sdkIdentity);
  const members = ['./sdk', './consumer'];
  const imports = ['"finos/morphir-sdk@0.1.0"'];
  const aliases = [];
  const tests = [];
  for (const [index, model] of output.models.entries()) {
    assert.match(model.id, /^[a-z]+$/);
    assert.match(model.function, /^[a-zA-Z_][a-zA-Z0-9_]*$/);
    assert.equal(model.expected.length, 4);
    assert.ok(model.expected.every(value => typeof value === 'boolean'));
    assert.deepEqual(model.scheme, model.expected);
    const originalModule = 'acceptance/original-' + model.id;
    const original = join(workspace, 'original-' + index);
    const generated = join(workspace, 'generated-' + index);
    mkdirSync(original); mkdirSync(generated);
    writeFileSync(join(original, 'moon.mod'), `name = "${originalModule}"\nversion = "0.0.0"\n`);
    writeFileSync(join(original, 'moon.pkg'), '');
    writeFileSync(join(original, 'original.mbt'), model.source);
    assert.deepEqual(model.artifacts.map(a => a.path).sort(), ['library.mbt', 'moon.mod', 'moon.pkg', 'symbols.10n']);
    for (const artifact of model.artifacts) {
      assert.ok(typeof artifact.content === 'string' || (Array.isArray(artifact.content) && artifact.content.every(b => Number.isInteger(b) && b >= 0 && b <= 255)));
      writeFileSync(join(generated, artifact.path), typeof artifact.content === 'string' ? artifact.content : Buffer.from(artifact.content));
    }
    members.push('./original-' + index, './generated-' + index);
    imports.push(JSON.stringify(originalModule + '@0.0.0'), JSON.stringify(model.module + '@0.1.0'));
    aliases.push(`"${originalModule}" @o${index}`, `"${model.module}" @g${index}`);
    const rows = [[false, false], [false, true], [true, false], [true, true]];
    tests.push(`///|\ntest "${model.id}: original, Scheme and generated agree" {\n` + rows.map(([active, vip], row) =>
      `  let original = @o${index}.decide(${active}, ${vip})\n  assert_eq(original, ${model.expected[row]})\n  assert_eq(@g${index}.${model.function}()(${active})(${vip}), original)\n`).join('') + '}\n');
  }
  mkdirSync(join(workspace, 'consumer'));
  writeFileSync(join(workspace, 'consumer/moon.mod'), `name = "acceptance/consumer"\nversion = "0.0.0"\nimport { ${imports.join(', ')} }\n`);
  writeFileSync(join(workspace, 'consumer/moon.pkg'), `import { ${aliases.join(', ')} }\n`);
  writeFileSync(join(workspace, 'consumer/acceptance_test.mbt'), tests.join('\n'));
  writeFileSync(join(workspace, 'moon.work'), `members = ${JSON.stringify(members)}\n`);
  for (const target of ['js', 'native', 'wasm', 'wasm-gc']) {
    for (const mode of ['debug', 'release']) {
      const args = ['test', '--frozen', '--target', target, '-p', 'acceptance/consumer'];
      if (mode === 'release') args.push('--release');
      const result = spawnSync(moon, args, {cwd: workspace, encoding: 'utf8', env, timeout: 300000, maxBuffer: 16777216});
      writeFileSync(join(receipts, `${target}-${mode}.log`), result.stdout + '\n' + result.stderr);
      assert.ok(!result.error, result.error?.message);
      assert.equal(result.status, 0, `${target}/${mode}: ${result.stdout}\n${result.stderr}`);
      assert.match(result.stdout, /Total tests: 11, passed: 11, failed: 0/);
      lanes.push({target, mode, tests: 11, truthTableRows: 44});
      console.log(`Boolean frontend ${target}/${mode}: 11 models, 44 rows passed`);
    }
  }
  const identities = {
    successful: true, profile: output.profile, parserVersion: output.parserVersion,
    compilerVersion: stableVersion, compilerIdentity: compilerIdentity(home),
    coreIdentity: treeIdentity(join(home, 'lib/core'), {core: true}),
    frontendIdentity: treeIdentity(join(repository, 'pkgs/morphir-moonbit-frontend')),
    generatorIdentity: treeIdentity(join(repository, 'pkgs/morphir-moonbit')),
    parserIdentity: treeIdentity(join(repository, '.mooncakes/moonbitlang/parser')),
    lexerIdentity: treeIdentity(join(repository, '.mooncakes/moonbitlang/lexer')),
    ionIdentity: treeIdentity(join(repository, '.mooncakes/moonrockz/ion')),
    sdk: {identity: sdkIdentity, semanticPin}, node: process.version,
    models: output.models.map(model => ({id: model.id, sourceIdentity: hash(model.source), irIdentity: hash(model.ir), artifactsIdentity: hash(JSON.stringify(model.artifacts))})),
    lanes,
  };
  writeFileSync(join(receipts, 'identity.json'), JSON.stringify(identities, null, 2) + '\n');
} finally {
  rmSync(workspace, {recursive: true, force: true});
}
