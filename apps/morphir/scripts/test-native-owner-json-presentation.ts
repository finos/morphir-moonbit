/** Current native-owner artifacts only. Build the seven release packages first.
 * Run with Node, after building protocol-fault for JS as well.
 * No historical Git objects, Rust, CEF, browser, service or network is used.
 */
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
const build = join(repo, '_build/native/release/build/finos');
const names = ['acceptance', 'bridge-acceptance', 'files-acceptance', 'fixture', 'mck/native', 'workspace-acceptance', 'protocol-fault'] as const;
type Owner = typeof names[number];
const executable = (name: Owner) => name === 'protocol-fault'
  ? join(build, 'morphir-host/acceptance/protocol-fault/protocol-fault.exe')
  : join(build, 'morphir-workbench-native', name, name.split('/').at(-1) + '.exe');
const scratch = mkdtempSync(join(tmpdir(), 'morphir-native-owner-json-'));
const receipts: Record<string, unknown>[] = [];
function run(name: Owner, argv: string[], options: { input?: Buffer | string; cwd?: string; program?: string; env?: NodeJS.ProcessEnv; timeout?: number } = {}) {
  const result = spawnSync(options.program ?? executable(name), argv, {
    cwd: options.cwd ?? repo, input: options.input ?? '', env: options.env ?? process.env,
    timeout: options.timeout ?? 30000, maxBuffer: 8 * 1024 * 1024,
  });
  receipts.push({ owner: name, argv, cwd: options.cwd ?? repo, status: result.status, signal: result.signal,
    stdoutBytes: result.stdout?.length, stderrBytes: result.stderr?.length,
    stdout: result.stdout?.length <= 4096 ? result.stdout.toString("base64") : undefined,
    stderr: result.stderr?.length <= 16384 ? result.stderr.toString() : undefined, error: result.error?.message });
  if (!options.timeout) assert.equal(result.error, undefined, result.error?.message);
  return result;
}
function success(result: ReturnType<typeof run>) {
  assert.equal(result.status, 0, result.stderr.toString() + result.stdout.toString());
  assert.equal(result.signal, null);
}
function value(result: ReturnType<typeof run>) {
  const source = result.stdout.toString();
  assert.ok(source.endsWith('\n'));
  const parsed = JSON.parse(source);
  assert.equal(source, JSON.stringify(parsed) + '\n', 'one compact JSON value plus LF');
  return parsed;
}
function envelope(result: ReturnType<typeof run>, status = 0) {
  assert.equal(result.status, status, result.stderr.toString());
  const parsed = value(result);
  assert.equal(parsed.profile, 'morphir/command-result');
  assert.equal(parsed.contractVersion, '0.1.0');
  assert.equal(parsed.exitCode, status);
  assert.equal(parsed.state, status === 0 ? 'succeeded' : 'failed');
  assert.deepEqual(parsed.diagnostics, []);
  assert.equal('result' in parsed, status === 0);
  assert.equal('error' in parsed, status !== 0);
  if (status !== 0) { assert.equal(typeof parsed.error.code, 'string'); assert.equal(typeof parsed.error.message, 'string'); }
  return parsed;
}
function events(result: ReturnType<typeof run>, terminalCode = 0) {
  const lines = result.stderr.toString().trim().split('\n').map(line => JSON.parse(line));
  assert.ok(result.stderr.length < 16384, 'bounded owner stderr');
  let prior = -1;
  for (const event of lines) {
    assert.equal(event.profile, 'morphir/command-event');
    assert.equal(event.contractVersion, '0.1.0');
    assert.ok(event.sequence > prior);
    prior = event.sequence;
  }
  assert.equal(lines[0].event, 'startup');
  assert.equal(lines.at(-1).event, 'terminal');
  assert.equal(lines.at(-1).exitCode, terminalCode);
  return lines;
}
// Ion 1.0 seed generated with the repository's pinned moonrockz/ion 0.5.0.
// It contains profile, suite_identity, calls one/two with value 42 and duration 0,
// traceparent and extensions. The test uses actual decoded/mutated binary files.
const seed = Buffer.from('4AEA6u7XgYPe04e+0Idwcm9maWxljo5zdWl0ZV9pZGVudGl0eYVjYWxsc4JpZIV2YWx1ZY6QZHVyYXRpb25fc2Vjb25kc4t0cmFjZXBhcmVudIpleHRlbnNpb25z3tOKjpNtb3JwaGlyLW91dGNvbWVzLXYxi4NhYmOMvqjeko2Db25ljiEqj0gAAAAAAAAAAN6SjYN0d2+OISqPSAAAAAAAAAAAkIV0cmFjZZGEa2VwdA==', 'base64');
try {
  for (const name of names) {
    assert.ok(existsSync(executable(name)), `Build current release artifact: ${name}`);
    const cwd = join(scratch, name.replaceAll('/', '-'));
    mkdirSync(cwd);
    const help = run(name, ['--json', '--help'], { cwd, input: 'must not be read' });
    success(help);
    const parsed = envelope(help);
    assert.match(parsed.result.render_help, /--json -- RAW/);
    assert.match(parsed.result.render_help, /--forward-argv -- RAW/);
    assert.match(parsed.result.render_help, /morphir\/command-result/);
    assert.match(parsed.result.render_help, /morphir\/command-event/);
    assert.equal(help.stderr.length, 0);
    assert.deepEqual(readdirSync(cwd), [], 'help has no filesystem effects');
  }
  const js = join(repo, '_build/js/debug/build/finos/morphir-host/acceptance/protocol-fault/protocol-fault.js');
  assert.ok(existsSync(js), 'Build current JS protocol-fault artifact');
  const faults = ['truncated', 'malformed', 'oversize', 'missing', 'extra', 'duplicate', 'reordered', 'wrong-id', 'duration', 'value', 'wrong-suite', 'wrong-profile', 'wrong-trace', 'extensions', 'duplicate-field'];
  for (const fault of faults) {
    const plain = join(scratch, fault + '-plain.ionb'), json = join(scratch, fault + '-json.ionb');
    writeFileSync(plain, seed); writeFileSync(json, seed);
    const oldMode = run('protocol-fault', [plain, fault, '--', '', '--json', '雪']);
    success(oldMode); assert.equal(oldMode.stdout.length, 0); assert.equal(oldMode.stderr.length, 0);
    const selected = run('protocol-fault', ['--json', '--', json, fault, '--', '', '--help', '--json', '雪']);
    const result = envelope(selected).result;
    assert.equal(selected.stderr.length, 0);
    assert.equal(result.fault, fault); assert.equal(result.path, json);
    assert.equal(result.bytesWritten, readFileSync(json).length);
    assert.deepEqual(readFileSync(json), readFileSync(plain), fault + ' unchanged artifact bytes');
    const jsPath = join(scratch, fault + '-js.ionb'); writeFileSync(jsPath, seed);
    const jsResult = run('protocol-fault', [js, '--json', '--', jsPath, fault], { program: process.execPath });
    assert.equal(envelope(jsResult).result.bytesWritten, readFileSync(jsPath).length);
    assert.deepEqual(readFileSync(jsPath), readFileSync(plain), fault + ' JS mutation bytes');
  }
  // Native and JS exercise the actual runtime-owned argv prefixes independently.
  for (const backend of ['native', 'js'] as const) {
    for (const path of ['--json', '--', '--help', '--forward-argv', 'spaces 雪 " $ ; `']) {
      writeFileSync(join(scratch, path), seed);
      const argv = ['--json', '--', path, 'malformed', '--', '', '--json'];
      const result = run('protocol-fault', backend === 'js' ? [js, ...argv] : argv, { cwd: scratch, program: backend === 'js' ? process.execPath : undefined });
      assert.equal(envelope(result).result.path, path);
      assert.deepEqual(readFileSync(join(scratch, path)), Buffer.from('not Ion'));
      // Legacy lone --json is a path, and the literal escape unwraps once.
      writeFileSync(join(scratch, path), seed);
      const raw = ['--forward-argv', '--', path, 'truncated'];
      success(run('protocol-fault', backend === 'js' ? [js, ...raw] : raw, { cwd: scratch, program: backend === 'js' ? process.execPath : undefined }));
      assert.deepEqual(readFileSync(join(scratch, path)), seed.subarray(0, -1));
    }
  }
  const untouched = join(scratch, 'untouched.ionb'); writeFileSync(untouched, seed);
  for (const argv of [[], ['missing'], ['', 'malformed'], [untouched, 'unknown'], [join(scratch, 'absent'), 'malformed'], [scratch, 'malformed']]) {
    envelope(run('protocol-fault', ['--json', '--', ...argv]), 1);
    assert.deepEqual(readFileSync(untouched), seed);
  }
  for (const bytes of [Buffer.from('not Ion'), Buffer.from([0xe0, 1, 0, 0xea, 0xd0])]) {
    const bad = join(scratch, 'invalid-codec.ionb'); writeFileSync(bad, bytes);
    envelope(run('protocol-fault', ['--json', '--', bad, 'wrong-id']), 1);
    assert.deepEqual(readFileSync(bad), bytes, 'codec/domain refusal preserves input');
  }
  const readOnly = join(scratch, 'read-only.ionb'); writeFileSync(readOnly, seed); chmodSync(readOnly, 0o400);
  try {
    envelope(run('protocol-fault', ['--json', '--', readOnly, 'malformed']), 1);
    assert.deepEqual(readFileSync(readOnly), seed, 'write failure cannot claim completion');
  } finally { chmodSync(readOnly, 0o600); }
  const empty = join(scratch, 'empty'); writeFileSync(empty, '');
  envelope(run('protocol-fault', ['--json', '--', empty, 'truncated']), 1);
  assert.equal(readFileSync(empty).length, 0);
  // All three native protocol owners keep exact stdout bytes for real requests.
  const request = JSON.stringify({ operation: 'evaluate', executionMode: 'typed',
    source: readFileSync(join(repo, 'apps/morphir-workbench/fixtures/typed-pricing.json'), 'utf8'),
    entry: 'pricing:scalars#huge', arguments: [] });
  const header = Buffer.alloc(4); header.writeUInt32BE(Buffer.byteLength(request));
  const binary = Buffer.concat([header, Buffer.from(request)]);
  for (const name of ['fixture', 'bridge-acceptance'] as const) {
    const raw = name === 'fixture' ? [] : ['--morphir-native-worker'];
    const plain = run(name, raw, { input: binary }); success(plain); assert.ok(plain.stdout.length > 4);
    const json = run(name, ['--json', '--', ...raw], { input: binary }); success(json);
    assert.deepEqual(json.stdout, plain.stdout, name + ' exact binary stdout');
    assert.equal(json.stdout.readUInt32BE(), json.stdout.length - 4);
    events(json);
    const broken = run(name, ['--json', '--', ...raw], { input: Buffer.from([0, 0, 0, 0]) });
    assert.equal(broken.status, 1); assert.equal(broken.stdout.length, 0); events(broken, 1);
  }
  const negotiation = JSON.stringify({ id: 1, op: 'capabilities', suite: 'workbench', contractVersion: '0.1.0-draft.18' }) + '\n' + '{"op":"exit"}\n';
  const plainMck = run('mck/native', ['foreign', '--', '', '--json'], { input: negotiation }); success(plainMck);
  const jsonMck = run('mck/native', ['--json', '--', 'foreign', '--', '', '--json'], { input: negotiation }); success(jsonMck);
  assert.deepEqual(jsonMck.stdout, plainMck.stdout); events(jsonMck);
  const filesInput = JSON.stringify({ profile: 'morphir/workbench/workspace-files', contractVersion: '0.1.0-draft.1', operation: 'session.open' }) + '\n';
  const plainFiles = run('files-acceptance', [scratch], { input: filesInput }); success(plainFiles);
  const jsonFiles = run('files-acceptance', ['--json', '--', scratch], { input: filesInput }); success(jsonFiles);
  assert.deepEqual(jsonFiles.stdout, plainFiles.stdout); events(jsonFiles);
  for (const name of ['files-acceptance', 'mck/native'] as const) {
    for (const input of ['incomplete', 'x'.repeat(name === 'files-acceptance' ? 1048577 : 2097153)]) {
      const result = run(name, ['--json', '--', ...(name === 'files-acceptance' ? [scratch] : [])], { input });
      assert.equal(result.status, 1); assert.equal(result.stdout.length, 0); events(result, 1);
    }
  }
  const missingFolder = run('files-acceptance', ['--json', '--']);
  assert.equal(missingFolder.status, 1); assert.equal(missingFolder.stdout.length, 0); events(missingFolder, 1);
  // Fault identities remain owned by argv[0], including deliberate status 7.
  for (const fault of ['fault-crash', 'fault-after', 'fault-frame', 'fault-stderr', 'fault-hang', 'fault-memory', 'fault-trailing', 'fault-late-cancel']) {
    const program = join(scratch, fault + '.exe'); copyFileSync(executable('fixture'), program); chmodSync(program, 0o700);
    const limited = !['fault-crash', 'fault-after'].includes(fault);
    const plain = run('fixture', [], { program, input: binary, timeout: limited ? 1500 : undefined });
    const json = run('fixture', ['--json', '--'], { program, input: binary, timeout: limited ? 1500 : undefined });
    assert.equal(json.status, plain.status); assert.equal(json.signal, plain.signal);
    assert.deepEqual(json.stdout, plain.stdout, fault + ' deliberate wire bytes');
    if (!limited) { assert.equal(json.status, 7); events(json, 7); }
    if (fault === 'fault-stderr') assert.ok(json.stderr.includes(Buffer.alloc(70000, 'x')), 'deliberate corruption remains');
  }
  // Run existing acceptance operations against actual current worker artifacts.
  const acceptance = run('acceptance', [executable('fixture')]); success(acceptance);
  const acceptanceJson = run('acceptance', ['--json', '--', 'ignored', '--', executable('fixture')]); success(acceptanceJson);
  assert.deepEqual(acceptanceJson.stdout, acceptance.stdout); assert.ok(value(acceptanceJson).cases > 0);
  const bridge = run('bridge-acceptance', []); success(bridge);
  const bridgeJson = run('bridge-acceptance', ['--json', '--']); success(bridgeJson);
  assert.deepEqual(bridgeJson.stdout, bridge.stdout);
  // The real parent still launches its fixed sentinel and bounds child stderr.
  // A test wrapper opts each copied fault fixture into diagnostics while keeping
  // argv[0] fault identity and every wire byte owned by the original executable.
  const reportingFixture = join(scratch, 'reporting-fixture');
  const quoteFixture = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  writeFileSync(reportingFixture, `#!/bin/bash\nexec -a "$0" ${quoteFixture(executable('fixture'))} --json -- "$@"\n`);
  chmodSync(reportingFixture, 0o700);
  const parentWithEvents = run('acceptance', ['--json', '--', reportingFixture]); success(parentWithEvents);
  assert.deepEqual(parentWithEvents.stdout, acceptance.stdout, 'bounded events preserve parent worker outcomes');
  // A copied executable stub records actual child argv/cwd/env/stdin before exit.
  for (const code of [23, 130]) {
    const stub = join(scratch, 'stub-' + code), receipt = join(scratch, 'stub-' + code + '.json');
    const script = `const fs=require('node:fs');const chunks=[];process.stdin.on('data',b=>chunks.push(b));process.stdin.on('end',()=>{fs.writeFileSync(${JSON.stringify(receipt)},JSON.stringify({argv:process.argv.slice(1),cwd:process.cwd(),marker:process.env.NATIVE_OWNER_MARKER??null,stdin:Buffer.concat(chunks).length}));process.exit(${code});});`;
    const quote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
    writeFileSync(stub, `#!/bin/sh\nexec ${quote(process.execPath)} --input-type=commonjs -e ${quote(script)} -- "$@"\n`);
    chmodSync(stub, 0o700);
    const result = run('acceptance', ['--json', '--', 'ignored', '--', '', stub], { env: { ...process.env, NATIVE_OWNER_CAPTURE: receipt, NATIVE_OWNER_MARKER: '雪' } });
    envelope(result, 1); // Owner assertions historically fail with outer status 1.
    const captured = JSON.parse(readFileSync(receipt, 'utf8'));
    assert.deepEqual(captured.argv, ['--morphir-native-worker']);
    assert.equal(captured.cwd, repo); assert.equal(captured.marker, null, "production worker intentionally clears inherited env"); assert.ok(captured.stdin > 4);
  }
  envelope(run('acceptance', ['--json', '--', join(scratch, 'absent-worker')]), 1);
  const workspace = run('workspace-acceptance', []); success(workspace);
  const workspaceJson = run('workspace-acceptance', ['--json', '--']); success(workspaceJson);
  assert.deepEqual(workspaceJson.stdout, workspace.stdout);
  // Human-facing child progress must stay off JSON stdout; child argv stays raw.
  const childBin = join(scratch, 'bin'); mkdirSync(childBin);
  const order = join(scratch, 'child-order');
  const shellQuote = (text: string) => "'" + text.replaceAll("'", "'\\''") + "'";
  for (const [name, program] of [['ln', '/bin/ln'], ['mkfifo', '/usr/bin/mkfifo']] as const) {
    const stub = join(childBin, name);
    writeFileSync(stub, `#!/bin/sh\nprintf '${name} progress\\n'\nprintf '${name}\\n' >> ${shellQuote(order)}\nexec ${shellQuote(program)} "$@"\n`);
    chmodSync(stub, 0o700);
  }
  const progress = run('workspace-acceptance', ['--json', '--'], { env: { ...process.env, PATH: childBin + ':' + process.env.PATH } });
  success(progress); assert.deepEqual(progress.stdout, workspace.stdout);
  assert.equal(progress.stderr.toString(), 'ln progress\nmkfifo progress\n');
  assert.equal(readFileSync(order, 'utf8'), 'ln\nmkfifo\n');
  const fixturePath = join(scratch, 'workspace 雪');
  const generated = run('workspace-acceptance', ['--json', '--', 'fixture', fixturePath]);
  assert.equal(envelope(generated).result.filesWritten, 7);
  assert.ok(existsSync(join(fixturePath, 'rich/morphir-ir.10n')));
  assert.deepEqual(readFileSync(join(fixturePath, 'rich/morphir-ir.10n')), readFileSync(join(fixturePath, 'rich/morphir-ir.ionb')));
  envelope(run('workspace-acceptance', ['--json', '--', 'fixture', empty]), 1);
  const race = join(scratch, 'race'); mkdirSync(join(race, 'root/active'), { recursive: true }); mkdirSync(join(race, 'outside'));
  const raced = run('workspace-acceptance', ['--json', '--', 'race', race]);
  assert.equal(envelope(raced).result.iterations, 150);
  assert.deepEqual(readdirSync(join(race, 'root')), ['active']);
  envelope(run('workspace-acceptance', ['--json', '--', 'race', join(scratch, 'missing-race')]), 1);
  console.log(JSON.stringify({ successful: true, platform: process.platform, arch: process.arch, backend: 'native + Node JS protocol-fault', invocations: receipts.length, faults: faults.length, receipts }));
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
