// Node-only current-artifact regression. Build the five mck/{js,native} hosts
// and apps/morphir-extension with the pinned moon toolchain before running.
// Optional PROTOCOL_JSON_BASELINE_DIR compares pre-edit artifact copies; no Git
// objects, release acquisition, CEF, browser, network or user profiles are used.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const build = resolve(root, process.env.PROTOCOL_JSON_BUILD_DIR ?? '_build');
const baseline = process.env.PROTOCOL_JSON_BASELINE_DIR;
const groups = ['', 'capabilities', 'capability-executions', 'selected', 'workspace-files'] as const;
const versions = ['0.1.0-draft.1', '0.1.0-draft.12', '0.1.0-draft.19', '0.1.0-draft.11', '0.1.0-draft.1'];
const scratch = mkdtempSync(join(tmpdir(), 'morphir-protocol-json-'));
const environment = { ...process.env, MORPHIR_JSON_PRESENTATION_FIXTURE: 'cwd Ω --json' };
interface Host { name: string; artifact: string; node: boolean; budget: number; input: Buffer; baselineName: string }
interface Observation { status: number | null; signal: string | null; stdoutBytes: number; stdoutSha256: string; stderrBytes: number }
interface Receipt { host: string; assertions: number; cases: { inputBytes: number; human: Observation; json: Observation }[]; defaultFailure: { status: number | null; signal: string | null } }
const receipts: Receipt[] = [];
const hosts: Host[] = [];
for (const [index, group] of groups.entries()) {
  for (const target of ['js', 'native'] as const) {
    const suffix = group ? `${group}/${target}` : target;
    const artifact = join(build, target, 'debug/build/finos/morphir-workbench/mck', suffix, target === 'js' ? 'js.js' : 'native.exe');
    if (target === 'native' && process.env.PROTOCOL_JSON_NATIVE !== '1') continue;
    const request = { id: 1, op: 'capabilities', suite: group === 'workspace-files' ? 'workbench-workspace-files' : 'workbench', contractVersion: versions[index] };
    hosts.push({ name: `workbench.mck${group ? `.${group}` : ''}.${target}`, artifact, node: target === 'js', budget: group ? 2097152 : 8389632,
      input: Buffer.from(`${JSON.stringify(request)}\n${JSON.stringify({ id: 2, op: 'exit' })}\n`), baselineName: `${suffix.replaceAll('/', '-')}.${target === 'js' ? 'js' : 'exe'}` });
  }
}
if (process.env.PROTOCOL_JSON_NATIVE === '1') {
  const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'morphir.initialize', params: { protocolVersions: ['0.1'], host: { name: 'test Ω', version: '1' } } });
  const frame = (text: string) => `Content-Length: ${Buffer.byteLength(text)}\r\n\r\n${text}`;
  const shutdown = JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'morphir.shutdown' });
  const exit = JSON.stringify({ jsonrpc: '2.0', method: 'morphir.exit' });
  hosts.push({ name: 'extension.mep', artifact: join(build, 'native/debug/build/finos/morphir-extension/morphir-extension.exe'), node: false, budget: 0,
    input: Buffer.from(frame(body) + frame(shutdown) + frame(exit)), baselineName: 'extension.exe' });
}
function command(host: Host, args: string[], artifact = host.artifact): [string, string[]] {
  return host.node ? [process.execPath, [artifact, ...args]] : [artifact, args];
}
function run(host: Host, args: string[], input: Buffer, artifact = host.artifact) {
  const [executable, argv] = command(host, args, artifact);
  const result = spawnSync(executable, argv, { cwd: scratch, env: environment, input, timeout: 15000, maxBuffer: 24 * 1024 * 1024 });
  assert.ifError(result.error);
  return result;
}
function events(host: Host, stderr: Buffer): Record<string, unknown>[] {
  const text = stderr.toString('utf8');
  assert.ok(text.endsWith('\n'));
  return text.trimEnd().split('\n').map((line, index) => {
    const value = JSON.parse(line) as Record<string, unknown>;
    assert.equal(JSON.stringify(value), line, 'one compact value per LF');
    assert.equal(value.profile, 'morphir/command-event');
    assert.equal(value.contractVersion, '0.1.0');
    assert.equal(value.command, host.name);
    assert.equal(value.sequence, index + 1);
    return value;
  });
}
async function noEffectsHelp(host: Host) {
  const [executable, argv] = command(host, ['--json', '--help']);
  const child = spawn(executable, argv, { cwd: scratch, env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
  const stdout: Buffer[] = [], stderr: Buffer[] = [];
  child.stdout.on('data', (data: Buffer) => stdout.push(data));
  child.stderr.on('data', (data: Buffer) => stderr.push(data));
  const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
  const code = await new Promise<number | null>((done, reject) => { child.on('error', reject); child.on('close', done); });
  clearTimeout(timeout);
  assert.equal(code, 0, 'help must exit while stdin stays open');
  assert.equal(Buffer.concat(stdout).length, 0, 'wire stdout must stay clean');
  const text = Buffer.concat(stderr).toString();
  const value = JSON.parse(text) as { profile: string; command: string; state: string; exitCode: number; result: { help: string } };
  assert.equal(JSON.stringify(value) + '\n', text);
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.command, host.name);
  assert.equal(value.state, 'succeeded');
  assert.equal(value.exitCode, 0);
  assert.match(value.result.help, /morphir\/command-event/);
  assert.match(value.result.help, /stderr/);
}
try {
  for (const host of hosts) {
    assert.ok(existsSync(host.artifact), `Build current artifact first: ${host.artifact}`);
    let assertions = 0;
    const observations: Receipt['cases'] = [];
    const summarize = (value: ReturnType<typeof run>): Observation => ({ status: value.status, signal: value.signal, stdoutBytes: value.stdout.length, stdoutSha256: createHash('sha256').update(value.stdout).digest('hex'), stderrBytes: value.stderr.length });
    const bad = host.budget ? Buffer.from('incomplete') : Buffer.from('Content-Length: 8\r\n\r\nx');
    const cases = [Buffer.alloc(0), host.input, bad];
    if (host.budget) cases.push(Buffer.from("{\n"));
    if (host.budget) cases.push(Buffer.from([0xff, 10]), Buffer.from('x'.repeat(host.budget + 1)));
    for (const input of cases) {
      const human = run(host, [], input);
      if (baseline) {
        const original = run(host, [], input, resolve(baseline, host.baselineName));
        assert.equal(human.status, original.status);
        assert.equal(human.signal, original.signal);
        assert.deepEqual(human.stdout, original.stdout);
        if (human.signal === 'SIGABRT') {
          // Native runtime backtraces include artifact paths and changed call
          // sites; compare the runtime diagnostic prefix and the actual signal.
          assert.equal(human.stderr.toString().split('\n')[0], original.stderr.toString().split('\n')[0]);
        } else assert.deepEqual(human.stderr, original.stderr);
      }
      const json = run(host, ['--json'], input);
      observations.push({ inputBytes: input.length, human: summarize(human), json: summarize(json) });
      if (input === host.input && host.budget) {
        const first = JSON.parse(human.stdout.toString().split('\n')[0]!) as { binding?: string };
        assert.equal(typeof first.binding, 'string', 'exercise an actual capability reply');
      }
      assert.equal(json.signal, null);
      if (human.status === 0) assert.deepEqual(json.stdout, human.stdout, 'presentation cannot change wire bytes');
      else assert.equal(json.stdout.length, 0, 'owned refusal diagnostics must stay off wire stdout');
      const rows = events(host, json.stderr);
      assert.equal(rows[0]?.event, 'startup');
      assert.equal(rows.at(-1)?.event, 'exit');
      if (human.status === 0) {
        assert.equal(json.status, 0);
        assert.equal(rows.at(-1)?.exitCode, 0);
        assert.equal(rows.some(row => row.event === 'failure'), false);
      } else {
        assert.equal(json.status, 1, 'expected JSON framing refusal becomes normal exit 1');
        assert.equal(rows.at(-1)?.exitCode, 1);
        assert.equal(rows.at(-2)?.event, 'failure');
        if (input === bad && host.budget && !host.node) {
          const detail = rows.at(-2)?.error as { message?: string };
          assert.match(detail.message ?? '', /incomplete NDJSON line/, 'retain the actual framing refusal');
        }
      }
      assertions++;
    }
    await noEffectsHelp(host);
    assertions++;
    const invalid = run(host, ['--json', '--unknown'], host.input);
    assert.equal(invalid.status, 2);
    assert.equal(invalid.stdout.length, 0);
    assert.equal(events(host, invalid.stderr)[0]?.event, 'failure');
    assertions++;
    if (host.budget) {
      for (const args of [['--forward-argv', '--', '--json', '', 'Ω', '--', '--help'], ['ignored', '', 'Ω', '--', '--json']]) {
        const literal = run(host, args, host.input);
        const ordinary = run(host, [], host.input);
        assert.deepEqual(literal.stdout, ordinary.stdout);
        assert.deepEqual(literal.stderr, ordinary.stderr);
        assert.equal(literal.status, ordinary.status);
        assertions++;
      }
      const opaque = run(host, ['--json', '--', '', 'Ω', '--', '--json', '--help'], host.input);
      assert.equal(opaque.status, 0);
      assert.deepEqual(opaque.stdout, run(host, [], host.input).stdout);
      assert.equal(events(host, opaque.stderr).at(-1)?.event, 'exit');
      assertions++;
    } else {
      const legacy = run(host, ['--help'], host.input);
      assert.equal(legacy.status, 2);
      assert.equal(legacy.stdout.length, 0);
      assertions++;
    }
    const failure = run(host, [], bad);
    receipts.push({ host: host.name, assertions, cases: observations, defaultFailure: { status: failure.status, signal: failure.signal } });
  }
  assert.deepEqual(readdirSync(scratch), [], 'help and protocol processes must not create cwd artifacts');
  // Exercise the exact current pure event adapter and its permanent fixtures,
  // without importing Proton, linking CEF or launching an application window.
  const fixture = join(scratch, 'desktop-pure');
  mkdirSync(fixture);
  writeFileSync(join(fixture, 'moon.mod'), 'name = "presentation-fixture"\nversion = "0.0.0"\n');
  writeFileSync(join(fixture, 'moon.pkg'), 'import { "moonbitlang/core/argparse", "moonbitlang/core/json", }\n');
  for (const file of ['json_presentation.mbt', 'json_presentation_wbtest.mbt']) {
    writeFileSync(join(fixture, file), readFileSync(join(root, 'apps/morphir-workbench-desktop/app', file)));
  }
  for (const target of ['native', 'js', 'wasm', 'wasm-gc']) {
    const tested = spawnSync('moon', ['test', '--target', target], { cwd: fixture, env: environment, encoding: 'utf8', timeout: 30000 });
    assert.ifError(tested.error);
    assert.equal(tested.status, 0, `${target} pure desktop fixtures: ${tested.stdout}${tested.stderr}`);
  }
  const result = { host: `${process.platform}/${process.arch}`, node: process.version, baselineCompared: Boolean(baseline), desktopPureFixtureTargets: ['native', 'js', 'wasm', 'wasm-gc'], receipts };
  if (process.env.PROTOCOL_JSON_RECEIPT) writeFileSync(process.env.PROTOCOL_JSON_RECEIPT, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({ ...result, receipts: receipts.map(({ cases: _cases, ...receipt }) => receipt) }));
} finally { rmSync(scratch, { recursive: true, force: true }); }
