import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { appendFileSync, copyFileSync, existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';

// This is a command-output regression, not a runtime, MEP, codec or MCK
// qualification. Its children are deliberately synthetic native Bun programs.
const names = ['codec-adapter-mck', 'package-codec-adapter', 'package-mep-extension',
  'portable-mep-check', 'portable-mep-cli', 'portable-mep-mck'] as const;
type Name = typeof names[number];
const hostModules = ['node-mep-cli.mjs', 'node-mep-stdio.mjs', 'node-mep-adapter.mjs', 'node-mep-worker.mjs',
  'mep-adapter.mjs', 'mep-frames.mjs', 'wasm-memory.mjs', 'node-artifacts.mjs', 'artifacts.mjs',
  'assembly.mjs', 'index.mjs', 'dist/bridge.mjs'];
const sha = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
const put = (path: string, data: string | Buffer) => {
  mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, data);
};
const copyExecutable = (from: string, to: string) => {
  mkdirSync(dirname(to), { recursive: true });
  try { linkSync(from, to); } catch { copyFileSync(from, to); }
};
const kit = {
  source: { package: { name: 'fixture/bool' }, sources: { documents: [{ text: 'fixture source 雪\n' }] } },
  plainIr: { fixture: true },
  consumer: { files: { 'moon.mod': 'fixture', 'moon.pkg': 'fixture', 'main.mbt': 'fixture' }, expectedStdout: 'fixture consumer passed\n' },
  expectedJsonArtifacts: { 'library.mbt': 'fixture library\n' },
};
type Journal = { program: string; args: string[]; cwd: string; path: string | undefined; moonHome: string | undefined; tmpdir: string | undefined; stdin?: string };

function stub() {
  const args = process.argv.slice(2);
  const program = basename(process.execPath).replace(/\.exe$/, '');
  appendFileSync(process.env['PORTABLE_JOURNAL']!, JSON.stringify({ program, args, cwd: process.cwd(),
    path: process.env['PATH'], moonHome: process.env['MOON_HOME'], tmpdir: process.env['TMPDIR'], ...(process.env['PORTABLE_PROBE_STDIN'] ? { stdin: readFileSync(0, 'utf8') } : {}) } satisfies Journal) + '\n');
  if (process.env['PORTABLE_FAIL_PROGRAM'] === program) {
    process.stdout.write('child failure stdout\n'); process.stderr.write('child failure stderr\n');
    process.exit(Number(process.env['PORTABLE_FAIL_CODE'] ?? '23'));
  }
  const block = process.env['PORTABLE_BLOCK_FILE'];
  if (block && (program === 'mck' || program === 'acceptance' || program === 'git' ||
    (program === 'node' && args.some(arg => arg.includes('node-package-'))))) mkdirSync(block, { recursive: true });
  const at = (flag: string) => args[args.indexOf(flag) + 1]!;
  const progress = () => { process.stdout.write(`fixture ${program} progress\n`); process.stderr.write(`fixture ${program} diagnostic\n`); };
  if (program === 'git') {
    if (args[0] === 'rev-parse') process.stdout.write('fixture-source-revision\n');
  } else if (program === 'moon') {
    if (args[0] === 'version') process.stdout.write('moon 0.1 fixture\nmoonc v0.10.16+b1a0e846e\n');
    else if (args[0] === 'run') process.stdout.write(process.env['PORTABLE_CORE']! + '\n');
    else if (args.includes('tree')) process.stdout.write('{"fixtureGraph":true}\n');
    else if (args.includes('--dry-run')) process.stdout.write('fixture recipe\n');
    else if (args.includes('run')) process.stdout.write(kit.consumer.expectedStdout);
    else progress();
  } else if (program === 'mck') {
    if (args.includes('guest-run')) {
      put(at('--report'), JSON.stringify({ qualified: true, suite: 'mep-guest', corpusSha256: process.env['MORPHIR_MEP_KIT_SHA256'], records: [
        { caseId: 'generate-retained', observed: { result: { artifacts: [{ path: 'library.mbt', content: 'fixture library\n', binary: false }] } } },
        { caseId: 'compile-ion', request: { fixture: true } },
      ] }));
    } else if (args.includes('run')) {
      put(at('--report'), JSON.stringify({ qualified: true, errors: [], records: [{ fixture: true }] }));
      if (args.some(arg => arg.includes('browser-byte-adapter'))) {
        put(args.at(-1)!, JSON.stringify({ shutdown: 'passed', preflight: 'passed', requests: 3 }));
      }
    }
    progress();
  } else if (program === 'acceptance') process.stdout.write('fixture local acceptance\n');
  else if (program === 'node' && args[0] === '-p') {
    process.stdout.write(args[1] === 'process.execPath' ? process.execPath + '\n' : '{"fixtureRuntime":true}\n');
  } else if (program === 'node' && args[0] === '--version') process.stdout.write('v24.22.0\n');
  else if (program === 'morphir' || (program === 'node' && args.includes('extension'))) {
    const operation = args[args.indexOf('extension') + 1];
    const source = args[args.indexOf('extension') + 2];
    const output = args.includes('--output') ? at('--output') : '';
    const pin = args.includes('--extension-pin') ? at('--extension-pin') : '';
    let code = 0; let error = ''; let result: unknown = {};
    if (args.includes('--cancel-file')) { code = 130; error = 'execution.cancelled'; }
    else if (args.includes('--timeout')) { code = 124; error = 'execution.deadline'; }
    else if (pin.includes('wrong-wasm')) { code = 2; error = 'extension.identity_mismatch'; }
    else if (pin.includes('component')) { code = 2; error = 'extension.unsupported_binding'; }
    else if (output === 'mixed') { code = 2; error = 'extension.unsupported_model_tuple'; }
    else if (output && existsSync(output)) { code = 2; error = 'extension.output_exists'; }
    else if (['lossy', 'broken', 'retired', 'tampered'].includes(output)) {
      code = 1; error = 'extension.operation_unsuccessful';
      result = { diagnostic: output === 'retired' ? 'moonbit_frontend.unsupported_profile' : 'data.lossy_conversion' };
    } else if (operation === 'compile') {
      assert.equal(source, 'src/main.mbt');
      put(join(output, 'model.ionb'), 'fixture model bytes\0');
      put(join(output, 'model-envelope.json'), JSON.stringify({ profile: 'morphir-model', payload: { sha256: 'f'.repeat(64) } }));
    } else if (operation === 'generate') {
      put(join(output, 'library.mbt'), 'fixture library\n');
      put(join(output, 'mep/source-model.ionb'), 'fixture model bytes\0');
    } else result = { capabilities: { cancellation: false } };
    process.stdout.write(JSON.stringify({ state: code ? 'failed' : 'completed', error, result,
      extension: { id: 'morphir-moonbit' }, access: { wireCancellation: false },
      lifecycle: { exitCode: code, workDirectoryEmpty: true, shutdown: 'acknowledged' },
      negotiated: { tuple: { codec: 'ion-binary' } } }) + '\n');
    process.exit(code);
  } else if (program === 'node' && args.some(a => a.includes('node-package-'))) {
    const codec = args.some(a => a.includes('node-package-codec-adapter'));
    const destination = args[codec ? 2 : 1]!;
    for (const profile of codec ? ['bytes-v1', 'bytes-diagnostics-v1'] : ['extension']) {
      put(join(destination, profile, 'model.wasm'), 'fixture wasm');
      put(join(destination, profile, 'manifest.ion'), 'fixture ion');
    }
    progress();
  } else if (program === 'node' && args.some(a => a.includes('saved-byte-preflight'))) progress();
  else progress();
}

async function regression() {
  const root = resolve(import.meta.dir, '..');
  const moon = Bun.which('moon');
  assert.ok(moon, 'Select the pinned MoonBit toolchain on PATH');
  const target = process.env['PORTABLE_JSON_TARGET'] ?? 'native';
  assert.ok(target === 'native' || target === 'wasm');
  const moonrun = Bun.which('moonrun'); assert.ok(moonrun);
  const version = Bun.spawnSync([moon, 'version', '--all']);
  assert.match(version.stdout.toString(), /0\.10\.16\+b1a0e846e/);
  assert.equal(Bun.version, '1.4.4');
  mkdirSync(join(root, '.dev'), { recursive: true });
  const scratch = mkdtempSync(join(root, '.dev/portable-json-'));
  const executable = process.platform === 'win32' ? '.exe' : '';
  const stubPath = join(scratch, 'stub' + executable);
  const compiled = Bun.spawnSync([process.execPath, 'build', import.meta.filename, '--compile', '--outfile', stubPath], { cwd: root });
  assert.equal(compiled.exitCode, 0, compiled.stderr.toString());
  const artifacts = new Map<Name, string>();
  const receipts: unknown[] = [];
  try {
    for (const name of names) {
      const builtResult: ReturnType<typeof Bun.spawnSync> = Bun.spawnSync([moon, 'build', `scripts/${name}.mbtx`, '--target', target], { cwd: root });
      assert.equal(builtResult.exitCode, 0, builtResult.stdout!.toString() + builtResult.stderr!.toString());
      artifacts.set(name, join(root, 'scripts/_build', `${name}.mbtx/${target}/debug/build/single/single.${target === 'native' ? 'exe' : 'wasm'}`));
    }
    let sequence = 0;
    function fixture() {
      const cwd = join(scratch, `case-${sequence++} 雪 $;`);
      const bin = join(cwd, 'bin');
      const journal = join(cwd, 'journal.jsonl');
      for (const name of ['moon', 'node', 'bun', 'mck', 'git']) copyExecutable(stubPath, join(bin, name + executable));
      const artifactsPath = join(cwd, 'saved --json 雪');
      for (const profile of ['extension', 'bytes-v1', 'bytes-diagnostics-v1']) {
        put(join(artifactsPath, profile, 'model.wasm'), 'fixture wasm');
        put(join(artifactsPath, profile, 'manifest.ion'), 'fixture ion');
      }
      for (const name of hostModules) put(join(cwd, 'pkgs/morphir-host/embedding', name), `fixture ${name}\n`);
      for (const name of ['apps/morphir/bin/morphir.js', 'apps/morphir/dist/morphir.js',
        'apps/morphir/build-provider/extension.mjs', 'apps/morphir/build-provider/supervision.mjs',
        'apps/morphir/build-provider/identity.mjs']) put(join(cwd, name), `fixture ${name}\n`);
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/finos/morphir-extension/acceptance/acceptance.exe'));
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/finos/morphir-extension/morphir-extension.exe'));
      // The filename is part of the existing primary CLI build path. Tell the
      // synthetic native child its role through a hardlink with that same name.
      copyExecutable(stubPath, join(cwd, '_build/native/release/build/morphir/morphir/morphir.exe'));
      const kitPath = join(cwd, 'kit --json 雪.json'); put(kitPath, JSON.stringify(kit));
      const workbench = join(cwd, 'workbench'); put(join(workbench, 'cases.json'), JSON.stringify({ formatVersion: '0.1.0-draft.26', cases: [{}] }));
      const runner = join(bin, 'mck' + executable);
      const env: Record<string, string | undefined> = { ...process.env,
        PATH: bin, MOON_HOME: 'fixture preserved moon home 雪', PORTABLE_COMMAND_STUB: '1',
        PORTABLE_JOURNAL: journal, PORTABLE_CORE: 'fixture core --json 雪',
        MORPHIR_CODEC_ARTIFACTS: artifactsPath, MORPHIR_CODEC_EVIDENCE: join(cwd, 'codec-evidence'),
        MORPHIR_MEP_ARTIFACTS: artifactsPath, MORPHIR_MEP_EVIDENCE: join(cwd, 'local-evidence'),
        MORPHIR_MEP_MCK_EVIDENCE: join(cwd, 'mck-evidence'), MORPHIR_MEP_CLI_EVIDENCE: join(cwd, 'cli-evidence'),
        MORPHIR_MCK_BIN: runner, MORPHIR_MCK_SHA256: sha(readFileSync(runner)),
        MORPHIR_MEP_KIT: kitPath, MORPHIR_MEP_KIT_SHA256: sha(readFileSync(kitPath)), MORPHIR_WORKBENCH_KIT: workbench,
      };
      return { cwd, env, journal };
    }
    type Fixture = ReturnType<typeof fixture>;
    function run(name: Name, argv: string[], f: Fixture) {
      const begin = performance.now();
      const child = Bun.spawnSync([...(target === 'wasm' ? [moonrun!] : []), artifacts.get(name)!, ...(target === 'wasm' ? ['--'] : []), ...argv], { cwd: f.cwd, env: f.env, stdin: Buffer.from('fixture stdin 雪\n'), timeout: 90_000 });
      const result = { code: child.exitCode, signal: child.signalCode, stdout: child.stdout.toString(), stderr: child.stderr.toString() };
      receipts.push({ name, argv, ...result, children: existsSync(f.journal) ? readFileSync(f.journal, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [], milliseconds: performance.now() - begin });
      return result;
    }
    function decoded(outcome: ReturnType<typeof run>, state: string, code: number) {
      assert.equal(outcome.code, code, outcome.stderr + outcome.stdout);
      const value = JSON.parse(outcome.stdout);
      assert.equal(outcome.stdout, JSON.stringify(value) + '\n', 'Exactly one compact JSON value plus LF');
      assert.equal(value.profile, 'morphir/command-result'); assert.equal(value.contractVersion, '0.1.0');
      assert.equal(value.state, state); assert.equal(value.exitCode, code); assert.deepEqual(value.diagnostics, []);
      if (state === 'succeeded') { assert.ok(value.result); assert.ok(!('error' in value)); }
      else { assert.equal(typeof value.error.message, 'string'); assert.ok(!('result' in value)); }
      return value;
    }
    const journal = (f: Fixture): Journal[] => existsSync(f.journal) ? readFileSync(f.journal, 'utf8').trim().split('\n').map(line => JSON.parse(line)) : [];
    for (const name of names) {
      const help = fixture();
      const rendered = decoded(run(name, ['--json', '--help'], help), 'succeeded', 0);
      assert.match(rendered.result.render_help, /Usage:/); assert.match(rendered.result.json_help, /error\.code\/message/);
      assert.deepEqual(journal(help), []);
      for (const argv of [['--json', '-h'], ['--json', '--help', '--json'], ['--json', 'help'], ['--json', 'help', '--help']]) decoded(run(name, argv, help), 'succeeded', 0);
      for (const argv of [['--json', '--unknown'], ['--json', '--json=literal']]) {
        decoded(run(name, argv, help), 'failed', 1); assert.deepEqual(journal(help), []);
      }
      const stdinProbe = fixture(); stdinProbe.env['PORTABLE_PROBE_STDIN'] = '1';
      stdinProbe.env['PORTABLE_FAIL_PROGRAM'] = 'moon';
      decoded(run(name, ['--json'], stdinProbe), 'failed', 23);
      assert.equal(journal(stdinProbe)[0]?.stdin, 'fixture stdin 雪\n');
      const success = fixture();
      const result = decoded(run(name, ['--json'], success), 'succeeded', 0);
      assert.equal(result.command, name.replaceAll('-', '.'));
      const launches = journal(success); assert.ok(launches.length > 0);
      assert.ok(launches.every(entry => entry.cwd === success.cwd || entry.cwd.startsWith(success.cwd + sep)));
      assert.ok(launches.some(entry => entry.path === success.env['PATH'] && entry.moonHome === success.env['MOON_HOME']));
      if (name.startsWith('package-')) {
        assert.equal(readFileSync(join(result.result.destination, 'core-graph.json'), 'utf8'), '{"fixtureGraph":true}\n');
        assert.equal(readFileSync(join(result.result.destination, 'recipe.txt'), 'utf8'), 'fixture recipe\n');
        assert.deepEqual(launches.map(entry => entry.program), ['moon', 'moon', 'moon', 'bun', 'node']);
      } else {
        const ion = name === 'portable-mep-cli' ? 'receipt.ion' : name === 'portable-mep-check' ? 'portable-receipt.ion' : 'qualification.ion';
        const directory = name === 'portable-mep-cli' ? 'cli-evidence' : name === 'portable-mep-check' ? 'local-evidence' : name === 'portable-mep-mck' ? 'mck-evidence' : 'codec-evidence';
        const text = readFileSync(join(success.cwd, directory, ion), 'utf8');
        assert.deepEqual(JSON.parse(text.slice(text.indexOf('::') + 2)), result.result);
      }
      if (name === 'portable-mep-mck') {
        const guests = launches.filter(entry => entry.args.includes('guest-run'));
        assert.equal(guests.length, 2); assert.ok(guests.every(entry => entry.path === '' && entry.moonHome === ''));
      }
      if (name === 'portable-mep-check') {
        const acceptance = launches.find(entry => entry.program === 'acceptance')!;
        assert.ok(acceptance); assert.ok(acceptance.args[1] === success.cwd);
      }
      if (name === 'portable-mep-cli') {
        const calls = launches.filter(entry => entry.args.includes('extension'));
        assert.equal(calls.length, 28); assert.ok(calls.every(entry => entry.args[0] === '--json' || entry.args[1] === '--json'));
        assert.ok(calls.every(entry => entry.tmpdir === join(entry.cwd, 'tmp')));
        assert.ok(result.result.hosts.every((host: { cases: unknown[] }) => host.cases.length === 14));
      }
      for (const code of [23, 130]) {
        const failure = fixture(); failure.env['PORTABLE_FAIL_PROGRAM'] = 'moon'; failure.env['PORTABLE_FAIL_CODE'] = String(code);
        const failed = run(name, ['--json'], failure);
        decoded(failed, 'failed', code); assert.match(failed.stderr, /child failure/); assert.equal(journal(failure).length, 1);
      }
      const laterFailure = fixture();
      laterFailure.env['PORTABLE_FAIL_PROGRAM'] = name === 'codec-adapter-mck' || name === 'portable-mep-mck' ? 'mck' : name === 'portable-mep-check' ? 'acceptance' : 'bun';
      decoded(run(name, ['--json'], laterFailure), 'failed', 23);
      const writeFailure = fixture();
      if (name.startsWith('package-')) {
        put(join(writeFailure.env['MORPHIR_CODEC_ARTIFACTS']!, 'core-graph.json'), 'placeholder');
        // A directory at the owned output path makes the actual completed write fail.
        const destination = name === 'package-codec-adapter' ? writeFailure.env['MORPHIR_CODEC_ARTIFACTS']! : writeFailure.env['MORPHIR_MEP_ARTIFACTS']!;
        rmSync(join(destination, 'core-graph.json'), { force: true });
        mkdirSync(join(destination, 'core-graph.json'));
      } else {
        const directory = name === 'codec-adapter-mck' ? 'codec-evidence' : name === 'portable-mep-check' ? 'local-evidence' : name === 'portable-mep-cli' ? 'cli-evidence' : 'mck-evidence';
        const file = name === 'portable-mep-check' ? 'portable-receipt.ion' : name === 'portable-mep-cli' ? 'receipt.ion' : 'qualification.ion';
        writeFailure.env['PORTABLE_BLOCK_FILE'] = join(writeFailure.cwd, directory, file);
      }
      decoded(run(name, ['--json'], writeFailure), 'failed', 1);
      assert.ok(journal(writeFailure).length > 0);
      const refusal = fixture();
      if (name.startsWith('package-')) refusal.env['PORTABLE_FAIL_PROGRAM'] = 'missing';
      else if (name === 'codec-adapter-mck') delete refusal.env['MORPHIR_MCK_BIN'];
      else if (name === 'portable-mep-cli') refusal.env['MORPHIR_MEP_KIT_SHA256'] = 'wrong';
      else if (name === 'portable-mep-mck') refusal.env['MORPHIR_MCK_SHA256'] = 'wrong';
      else mkdirSync(refusal.env['MORPHIR_MEP_EVIDENCE']!);
      if (!name.startsWith('package-')) { decoded(run(name, ['--json'], refusal), 'failed', 1); assert.equal(journal(refusal).length, 0); }
      const missing = fixture(); missing.env['PATH'] = join(missing.cwd, 'no-tools');
      decoded(run(name, ['--json'], missing), 'failed', 1);
      // Legacy wrappers ignored operands. Neither variadic parsing nor new JSON
      // dispatch may reinterpret an escaped flag or rebuild a foreign tail.
      if (name !== 'portable-mep-cli') {
        const defaults = fixture();
        const legacy = run(name, ['--', '--json', '', '雪', '--', '--help', '--json=literal'], defaults);
        assert.equal(legacy.code, 0, legacy.stdout + legacy.stderr);
        assert.throws(() => JSON.parse(legacy.stdout));
        const escaped = fixture();
        decoded(run(name, ['--json', '--', '--json', '', '雪', '--', '--help'], escaped), 'succeeded', 0);
      }
      const legacyFailure = run(name, [], writeFailure);
      assert.notEqual(legacyFailure.code, 0, 'Default failure retains its backend presentation');
      const baseline = target === 'native' ? process.env['PORTABLE_JSON_BASELINE'] : undefined;
      if (baseline) {
        const f = fixture();
        const candidate = run(name, [], f);
        assert.equal(candidate.code, 0, candidate.stdout + candidate.stderr);
        const candidateChildren = journal(f);
        rmSync(f.journal, { force: true });
        const snapshots = new Map<string, Buffer>();
        function snapshot(directory: string) {
          if (!existsSync(directory)) return;
          for (const entry of readdirSync(directory, { withFileTypes: true })) {
            const file = join(directory, entry.name);
            if (entry.isDirectory()) snapshot(file); else snapshots.set(file, readFileSync(file));
          }
        }
        for (const key of ['MORPHIR_CODEC_EVIDENCE', 'MORPHIR_MEP_EVIDENCE', 'MORPHIR_MEP_MCK_EVIDENCE', 'MORPHIR_MEP_CLI_EVIDENCE']) snapshot(f.env[key]!);
        if (name.startsWith('package-')) for (const file of ['core-graph.json', 'recipe.txt']) snapshots.set(join(f.env['MORPHIR_CODEC_ARTIFACTS']!, file), readFileSync(join(f.env['MORPHIR_CODEC_ARTIFACTS']!, file)));
        for (const key of ['MORPHIR_CODEC_EVIDENCE', 'MORPHIR_MEP_EVIDENCE', 'MORPHIR_MEP_MCK_EVIDENCE', 'MORPHIR_MEP_CLI_EVIDENCE']) rmSync(f.env[key]!, { recursive: true, force: true });
        const original = artifacts.get(name)!;
        artifacts.set(name, join(baseline, name + '.exe'));
        const old = run(name, [], f);
        assert.deepEqual(old, candidate, 'Default success bytes and status must match the supplied baseline');
        assert.deepEqual(journal(f), candidateChildren, 'Default child argv/cwd/env/order must match');
        for (const [file, bytes] of snapshots) assert.deepEqual(readFileSync(file), bytes, file);
        artifacts.set(name, original);
        artifacts.set(name, join(baseline, name + '.exe'));
        const baselineFailure = run(name, [], writeFailure);
        assert.equal(baselineFailure.code, legacyFailure.code);
        assert.equal(baselineFailure.signal, legacyFailure.signal);
        artifacts.set(name, original);
        if (name === 'portable-mep-cli') {
          const now = run(name, ['--help'], f); artifacts.set(name, join(baseline, name + '.exe'));
          assert.deepEqual(run(name, ['--help'], f), now); artifacts.set(name, original);
        }
      }
      console.log(`${name}: completed result, help, refusals, child 23/130, channels and legacy operands passed`);
    }
    const receiptPath = process.env['PORTABLE_JSON_RECEIPTS'];
    if (receiptPath) put(receiptPath, JSON.stringify({ toolchain: version.stdout.toString(), bun: Bun.version, platform: process.platform, arch: process.arch, target, receipts }, null, 2) + '\n');
  } finally { rmSync(scratch, { recursive: true, force: true }); }
}

if (process.env['PORTABLE_COMMAND_STUB'] === '1') stub();
else await regression();
