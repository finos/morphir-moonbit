import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {delimiter, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Application regression: build each current artifact once, then exercise explicit
// argv against it. Historical source/artifact comparisons belong in local receipts.
const repository = fileURLToPath(new URL('../../../', import.meta.url));
assert.ok(process.env.MOON_HOME, 'Set MOON_HOME to the pinned MoonBit installation');
const home = resolve(process.env.MOON_HOME);
const moon = join(home, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon');
const moonrun = join(home, 'bin', process.platform === 'win32' ? 'moonrun.exe' : 'moonrun');
const env = {...process.env, MOON_HOME: home, PATH: join(home, 'bin') + delimiter + process.env.PATH};
const node = process.env.MORPHIR_FINITE_NODE || 'node';
const target = process.env.MORPHIR_FINITE_TARGET || 'js';
assert.ok(['native', 'js', 'wasm', 'wasm-gc'].includes(target));
const section = process.env.MORPHIR_FINITE_SECTION || 'all';
assert.ok(['all', 'finite', 'telemetry'].includes(section));
const receipts = resolve(repository, process.env.MORPHIR_FINITE_RECEIPTS || `.dev/finite-json/tests-${target}`);
mkdirSync(receipts, {recursive: true});
const scratch = mkdtempSync(join(tmpdir(), 'morphir-finite-json-'));
const cases: object[] = [];
let sequence = 0;

function build(paths: string[], backend: string) {
  const result = spawnSync(moon, ['build', '--frozen', '--target', backend, ...paths], {
    cwd: repository, env, encoding: 'utf8', timeout: 300000, maxBuffer: 16 * 1024 * 1024,
  });
  writeFileSync(join(receipts, `build-${backend}-${sequence++}.log`), result.stdout + result.stderr);
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
}

function artifact(path: string, backend: string): string[] {
  const components = path.split('/');
  const module = components[1];
  const name = components.at(-1);
  assert.ok(module && name);
  const extension = backend === 'js' ? 'js' : backend === 'native' ? 'exe' : 'wasm';
  const binary = join(repository, '_build', backend, 'debug/build/finos', module,
    ...components.slice(2), `${name}.${extension}`);
  return backend === 'js' ? [node, binary] : backend === 'native' ? [binary] : [moonrun, binary, '--'];
}

function run(command: string[], argv: string[], label: string, input: Uint8Array = new Uint8Array(),
  extraEnv: NodeJS.ProcessEnv = {}) {
  const [program, ...prefix] = command;
  assert.ok(program);
  const result = spawnSync(program, [...prefix, ...argv], {
    cwd: scratch, env: {...env, ...extraEnv}, input, encoding: 'utf8', timeout: 180000, maxBuffer: 32 * 1024 * 1024,
  });
  assert.equal(result.error, undefined, `${label}: ${result.error?.message}`);
  record(label, command, argv, result.status, result.signal, result.stdout, result.stderr);
  return result;
}

function record(label: string, command: string[], argv: string[], status: number | null,
  signal: string | null, stdout: string, stderr: string) {
  const id = `${sequence++}-${label.replaceAll(/[^a-zA-Z0-9.-]/g, '_')}`;
  writeFileSync(join(receipts, `${id}.stdout`), stdout);
  writeFileSync(join(receipts, `${id}.stderr`), stderr);
  cases.push({label, command, argv, cwd: scratch, status, signal, stdout: `${id}.stdout`, stderr: `${id}.stderr`,
    stdoutSha256: createHash('sha256').update(stdout).digest('hex'), stderrSha256: createHash('sha256').update(stderr).digest('hex')});
}

function json(stdout: string): Record<string, unknown> {
  const value: unknown = JSON.parse(stdout);
  assert.ok(value && typeof value === 'object' && !Array.isArray(value));
  assert.equal(stdout, JSON.stringify(value) + '\n', 'One compact JSON object followed by LF');
  return value as Record<string, unknown>;
}

function result(value: Record<string, unknown>): Record<string, unknown> {
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.state, 'succeeded');
  assert.equal(value.exitCode, 0);
  assert.deepEqual(value.diagnostics, []);
  assert.ok(value.result && typeof value.result === 'object');
  assert.ok(!('error' in value));
  return value.result as Record<string, unknown>;
}

function failure(command: string[], argv: string[], label: string, input?: Uint8Array) {
  const invocation = run(command, argv, label, input);
  assert.equal(invocation.status, 1, invocation.stderr);
  const value = json(invocation.stdout);
  assert.equal(value.state, 'failed');
  assert.equal(value.exitCode, 1);
  assert.equal(value.profile, 'morphir/command-result');
  assert.ok(value.error && typeof value.error === 'object');
  assert.ok(!('result' in value));
  return invocation;
}

const bare = [
  'pkgs/morphir-elm/acceptance', 'pkgs/morphir-engine/acceptance',
  'pkgs/morphir-engine/acceptance/elm', 'pkgs/morphir-engine/acceptance/inference',
  'pkgs/morphir-moonbit/acceptance', 'pkgs/morphir-moonbit-frontend/acceptance',
  'pkgs/morphir-moonbit-frontend/library-acceptance', 'pkgs/morphir-moonbit-frontend/typed-acceptance',
  'pkgs/morphir-host/assembly/qualification',
];
const text = ['pkgs/morphir-engine/data/examples', 'pkgs/morphir-engine/examples',
  'pkgs/morphir-host/acceptance/metadata-fixture'];

try {
  if (section !== 'telemetry') {
  const portable = [...bare, ...text].filter(path => !path.endsWith('assembly/qualification'));
  build(portable, target);
  build(['pkgs/morphir-host/assembly/qualification'], 'js');
  for (const path of [...bare, ...text]) {
    const command = artifact(path, path.endsWith('assembly/qualification') ? 'js' : target);
    const ordinary = run(command, [], `${path}-default`);
    assert.equal(ordinary.status, 0, ordinary.stderr);
    assert.equal(ordinary.stderr, '');
    const ignored = run(command, ['--', '--json', '', 'λ😀', '--help'], `${path}-legacy-literals`);
    assert.equal(ignored.status, 0);
    assert.equal(ignored.stdout, ordinary.stdout);
    for (const legacyArgv of [['--help'], ['--self-test'], ['--', '--json']]) {
      const legacy = run(command, legacyArgv, `${path}-legacy-control`);
      assert.equal(legacy.status, 0);
      assert.equal(legacy.stdout, ordinary.stdout);
    }
    const invocation = run(command, ['--json'], `${path}-json`);
    assert.equal(invocation.status, 0, invocation.stderr);
    assert.equal(invocation.stderr, '');
    const value = json(invocation.stdout);
    if (bare.includes(path)) {
      assert.equal(invocation.stdout, ordinary.stdout, 'Existing bare JSON schema and bytes');
    } else if (path.endsWith('morphir-engine/examples')) {
      const generated = result(value);
      assert.deepEqual(generated.diagnostics, []);
      assert.deepEqual(generated.artifacts, [{source: 'demo/src/main.scm', path: 'demo/dist/main.ir.json', evaluation: '42'}]);
      assert.equal(ordinary.stdout, 'demo/src/main.scm -> demo/dist/main.ir.json\nresult: 42\n');
    } else {
      const generated = result(value);
      assert.equal(generated.codec, 'ion-text');
      assert.equal(ordinary.stdout, String(generated.checkpoint) + '\n');
    }
    const help = run(command, ['--json', '--help'], `${path}-help`);
    assert.equal(help.status, 0);
    assert.equal(typeof result(json(help.stdout)).help, 'string');
    assert.equal(help.stderr, '');
    const selftest = run(command, ['--json', '--self-test'], `${path}-self-test`);
    assert.equal(selftest.status, 0, selftest.stderr);
    const tested = result(json(selftest.stdout));
    assert.equal(tested.passed, true);
    assert.deepEqual(tested.output, bare.includes(path) ? value : result(value));
    for (const argv of [['--json', '--unknown'], ['--json', '--help', '--unknown'],
      ['--json', ''], ['--json', '--', '--help'], ['--json', 'λ😀']]) {
      assert.equal(failure(command, argv, `${path}-syntax`).stderr, '');
    }
  }

  const extension = 'apps/morphir-extension/acceptance';
  build([extension], 'native');
  const extensionCommand = artifact(extension, 'native');
  for (const control of ['--help', '-h', '--self-test']) {
    const invocation = run(extensionCommand, ['--json', control], `extension-${control}`);
    assert.equal(invocation.status, 0);
    const output = result(json(invocation.stdout));
    if (control === '--self-test') { assert.equal(output.passed, true); assert.equal(output.cases, 3); }
    else { assert.equal(typeof output.help, 'string'); }
  }
  for (const argv of [['--json'], ['--json', '--unknown'], ['--json', '', 'λ😀', '--'],
    ['--json', '--json', '--help', '--'], ['--json', '--', '--json', '--help', '--']]) {
    failure(extensionCommand, argv, 'extension-failure');
  }
  const legacy = run(extensionCommand, ['--json', '--help', '--'], 'extension-literal-json-guest');
  assert.ok(legacy.status !== 0 || legacy.signal !== null);
  assert.equal(legacy.stdout, '', 'The complete triple remains literal legacy data');
  const stub = join(scratch, 'guest.mjs');
  const stubReceipt = join(scratch, 'guest-receipt.json');
  writeFileSync(stub, `import {writeFileSync} from 'node:fs';
writeFileSync(process.env.FINITE_STUB_RECEIPT, JSON.stringify({argv:process.argv.slice(2),cwd:process.cwd(),marker:process.env.FINITE_STUB_MARKER}));
process.stdout.write('child stdout remains collected protocol data');
process.stderr.write('child stderr fixture');process.exit(23);\n`);
  const nodeIdentity = spawnSync(node, ['-p', 'process.execPath'], {env, encoding: 'utf8'});
  assert.equal(nodeIdentity.status, 0, nodeIdentity.stderr);
  const stubResult = run(extensionCommand, ['--json', nodeIdentity.stdout.trim(), repository, join(scratch, 'evidence')],
    'extension-stub-failure', undefined, {MORPHIR_MEP_GUEST_ARGS: JSON.stringify([stub, '--json', '--', '', 'λ😀']),
      MORPHIR_MEP_GUEST_ENV: JSON.stringify({FINITE_STUB_RECEIPT: stubReceipt, FINITE_STUB_MARKER: 'explicit'})});
  assert.equal(stubResult.status, 1);
  assert.equal(json(stubResult.stdout).state, 'failed');
  assert.ok(!stubResult.stdout.includes('child stdout'));
  const child: {argv: string[]; cwd: string; marker: string} = JSON.parse(readFileSync(stubReceipt, 'utf8'));
  assert.deepEqual(child.argv, ['--json', '--', '', 'λ😀']);
  assert.equal(child.marker, 'explicit');
  assert.match(child.cwd.replaceAll('\\', '/'), /morphir-mep-acceptance-[^/]+\/process$/);

  }

  // Native telemetry builds separately from moon.work. Its existing setup owns
  // dependency acquisition; tests consume the explicit current artifact only.
  const otel = process.env.MORPHIR_FINITE_OTEL_BINARY;
  if (section !== 'finite' && otel) {
    const command = [resolve(otel)];
    for (const control of ['--help', '-h', '--self-test']) {
      const invocation = run(command, ['--json', control], `otel-${control}`);
      assert.equal(invocation.status, 0);
      const output = result(json(invocation.stdout));
      if (control === '--self-test') { assert.equal(output.passed, true); assert.equal(output.cases, 4); }
      else { assert.equal(typeof output.help, 'string'); }
    }
    for (const argv of [['--json'], ['--json', '--unknown'], ['--json', '', '', ''],
      ['--json', '--json', '--help', '--'], ['--json', '--', '--json', '--help', '--'],
      ...['0', '5001', 'bad', '-1', '--help', '--'].map(timeout => ['--json', 'http://127.0.0.1', 'http/json', timeout]),
      ['--json', 'http://127.0.0.1', '--help', '1'], ['--json', 'file:///tmp/local', 'http/json', '1']]) {
      assert.equal(failure(command, argv, 'otel-failure').stderr, 'observability.native_export_failed\n');
    }
    const literal = run(command, ['--json', '--help', '--'], 'otel-literal-json-endpoint');
    assert.equal(literal.status, 1);
    assert.equal(literal.stdout, '');
    assert.equal(literal.stderr, 'observability.native_export_failed\n');
    // Empty Ion datagram: real SDK construction, collection, flush and shutdown;
    // no exporter request is needed for the resulting empty batches.
    for (const protocol of ['http/json', 'http/protobuf']) {
      const invocation = run(command, ['--json', 'http://127.0.0.1:1', protocol, '1'], 'otel-empty-batch',
        Buffer.from([0xe0, 1, 0, 0xea]));
      assert.equal(invocation.status, 0, invocation.stderr);
      assert.deepEqual(result(json(invocation.stdout)), {spans: 0, logs: 0, metricBatches: 0,
        protocol, completion: 'exportersFlushedAndShutdown'});
    }
    // Generated by pinned ion/json + ion/binary from one completed observation
    // and one metrics row, using explicit Ion floats for the numeric fields.
    const fixture = Buffer.from('4AEA6u4Bo4GD3gGeh74Bmodwcm9maWxlhXN0YWdlhnNpZ25hbIx3YWxsX3NlY29uZHOOkGR1cmF0aW9uX3NlY29uZHOHc3Bhbl9pZIh0cmFjZV9pZIlwYXJlbnRfaWSLY29ycmVsYXRpb26KZGltZW5zaW9uc4Z0YXJnZXSIcHJvdmlkZXKHb3V0Y29tZYVjb3VudI6UZHVyYXRpb25fc2Vjb25kc19zdW3e+IqOlm1vcnBoaXItb2JzZXJ2YXRpb24tdjGLhGNhbGyMiWNvbXBsZXRlZI1IP/AAAAAAAACOSD/gAAAAAAAAj46QMDAwMDAwMDAwMDAwMDAwMZCOoDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAxkYCSD97Qio6SbW9ycGhpci1tZXRyaWNzLXYxk7643raLhGNhbGyUhm5hdGl2ZZWHZml4dHVyZZaJc3VjY2VlZGVkl0g/8AAAAAAAAJhIP+AAAAAAAAA=', 'base64');
    {
      const received: string[] = [];
      let refuse = false;
      const server = createServer(async (request, response) => {
        const chunks: Buffer[] = [];
        for await (const chunk of request) { chunks.push(Buffer.from(chunk)); }
        assert.equal(request.headers['content-type'], 'application/json');
        assert.ok(Buffer.concat(chunks).length > 0);
        received.push(request.url || '');
        response.writeHead(refuse ? 500 : 200, {'content-type': 'application/json'}).end('{}');
      });
      await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
      try {
        const address = server.address();
        assert.ok(address && typeof address !== 'string');
        const argv = ['--json', `http://127.0.0.1:${address.port}`, 'http/json', '1000'];
        const invoke = () => new Promise<{status: number | null; signal: string | null; stdout: string; stderr: string}>((resolve, reject) => {
          const child = spawn(command[0]!, argv, {cwd: scratch, env});
          let stdout = '', stderr = '';
          const timer = setTimeout(() => { child.kill(); reject(Error('Telemetry fixture timeout')); }, 10000);
          child.stdout.on('data', chunk => stdout += chunk);
          child.stderr.on('data', chunk => stderr += chunk);
          child.on('error', error => { clearTimeout(timer); reject(error); });
          child.on('close', (status, signal) => { clearTimeout(timer); resolve({status, signal, stdout, stderr}); });
          child.stdin.end(fixture);
        });
        const observed = await invoke();
        record('otel-local-collector', command, argv, observed.status, observed.signal, observed.stdout, observed.stderr);
        assert.equal(observed.status, 0, observed.stderr);
        assert.deepEqual(result(json(observed.stdout)), {spans: 1, logs: 1, metricBatches: 2,
          protocol: 'http/json', completion: 'exportersFlushedAndShutdown'});
        assert.deepEqual(received, ['/v1/traces', '/v1/logs', '/v1/metrics']);
        refuse = true;
        const failed = await invoke();
        record('otel-exporter-refusal', command, argv, failed.status, failed.signal, failed.stdout, failed.stderr);
        assert.equal(failed.status, 1);
        const failure = json(failed.stdout);
        assert.equal(failure.state, 'failed');
        assert.equal(failure.exitCode, 1);
        assert.ok(!('result' in failure));
        assert.equal(failed.stderr, 'observability.native_export_failed\n');
      } finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
    }
  } else if (section === 'telemetry') {
    assert.fail('Telemetry qualification requires MORPHIR_FINITE_OTEL_BINARY');
  } else if (section !== 'finite') { console.log('Native telemetry not executed: supply MORPHIR_FINITE_OTEL_BINARY'); }
  console.log(`${cases.length} finite command cases passed on ${process.platform}/${process.arch}, target ${target}`);
} finally {
  writeFileSync(join(receipts, 'cases.json'), JSON.stringify({target, host: `${process.platform}/${process.arch}`, cases}, null, 2) + '\n');
  rmSync(scratch, {recursive: true, force: true});
}
