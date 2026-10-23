// Node-only current-artifact regression. Build the five mck/{js,native} hosts
// and apps/morphir-extension with the pinned moon toolchain before running.
// Optional PROTOCOL_JSON_BASELINE_DIR compares pre-edit artifact copies; no Git
// objects, release acquisition, CEF, browser, network or user profiles are used.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { release, tmpdir, version } from 'node:os';
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
interface LargeDiagnostic { optionCodeUnits: number; optionBytes: number; stderrBytes: number; status: number; signal: null; stdoutBytes: number }
interface Receipt { host: string; largeDiagnostic?: LargeDiagnostic; assertions: number; cases: { inputBytes: number; human: Observation; json: Observation }[]; defaultFailure: { status: number | null; signal: string | null } }
type Stage = 'native-binary-mode-prototype' | 'native-byte-probe' | 'artifact' | 'protocol-case' | 'help' | 'invalid-option' | 'large-diagnostic' | 'forward-argv' | 'opaque-argv' | 'legacy-help' | 'default-failure' | 'cwd-check' | 'pure-setup' | 'pure-test' | 'receipt';
let context: { stage: Stage; host?: string; case?: number; inputBytes?: number; target?: string; executable?: string; argv?: string[]; commands?: { executable: string; argv: string[] }[]; cwd?: string } = { stage: 'artifact' };
let failure: { error: unknown } | undefined;
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
  const [executable, argv]: [string, string[]] = host.node ? [process.execPath, [artifact, ...args]] : [artifact, args];
  context = { ...context, host: host.name, executable, argv, commands: [...(context.commands ?? []), { executable, argv }], cwd: scratch };
  return [executable, argv];
}
function run(host: Host, args: string[], input: Buffer, artifact = host.artifact) {
  const [executable, argv] = command(host, args, artifact);
  context.inputBytes = input.length;
  const result = spawnSync(executable, argv, { cwd: scratch, env: environment, input, timeout: 15000, maxBuffer: 24 * 1024 * 1024 });
  if (result.error) console.error('Protocol process output', result.stdout?.toString(), result.stderr?.toString());
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
// Windows CreateProcess limits the whole command line to 32,767 UTF-16 units.
// Use three-byte UTF-8 characters there to exceed the observed 64 KiB pipe
// boundary without requesting an impossible 120,000-character OS argument.
// Reserve space for executable/script paths, quoting and the owned prefix.
async function largeSyntaxDiagnostic(host: Host, shortMessage: string): Promise<LargeDiagnostic> {
  const count = process.platform === 'win32'
    ? Math.min(24000, 30000 - process.execPath.length - host.artifact.length)
    : 120000;
  const option = '--' + (process.platform === 'win32' ? '界' : 'x').repeat(Math.max(0, count));
  assert.ok(Buffer.byteLength(option) > 65536, 'paths must leave enough Windows argv space for a diagnostic above 64 KiB');
  const [executable, argv] = command(host, ['--json', option]);
  const child = spawn(executable, argv, { cwd: scratch, env: environment, stdio: ['pipe', 'pipe', 'pipe'] });
  const stdout: Buffer[] = [], stderr: Buffer[] = [];
  child.stdout.on('data', (data: Buffer) => stdout.push(data));
  // Delay consumption so the write must survive actual backpressure. Keep
  // stdin open: argument rejection must finish without starting the server.
  child.stderr.pause();
  child.stderr.on('data', (data: Buffer) => stderr.push(data));
  const resume = setTimeout(() => child.stderr.resume(), 100);
  const timeout = setTimeout(() => child.kill('SIGKILL'), 10000);
  let status: number | null, signal: NodeJS.Signals | null;
  try {
    [status, signal] = await new Promise<[number | null, NodeJS.Signals | null]>((done, reject) => {
      child.on('error', reject);
      child.on('close', (code, exitSignal) => done([code, exitSignal]));
    });
  } finally { clearTimeout(resume); clearTimeout(timeout); }
  assert.equal(status, 2, 'large syntax rejection exits 2 while stdin stays open');
  assert.equal(signal, null);
  assert.equal(Buffer.concat(stdout).length, 0, 'syntax diagnostics cannot contaminate wire stdout');
  const diagnostic = Buffer.concat(stderr);
  assert.ok(diagnostic.length > 65536, 'exercise a diagnostic larger than the observed pipe boundary');
  const rows = events(host, diagnostic);
  assert.equal(rows.length, 1, 'one complete syntax failure event');
  assert.equal(rows[0]?.event, 'failure');
  assert.equal(rows[0]?.exitCode, 2);
  const error = rows[0]?.error as { code: string; message: string };
  assert.equal(error.code, 'argument_error');
  assert.equal(error.message, shortMessage.replace('--unknown', option), 'retain the entire parser diagnostic without redaction');
  return { optionCodeUnits: option.length, optionBytes: Buffer.byteLength(option), stderrBytes: diagnostic.length, status, signal, stdoutBytes: 0 };
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
// This opt-in observes the native runtime's physical stdout framing. It never
// qualifies strict LF, even when these two samples happen to end in LF.
function nativeByteSummary(bytes: Buffer) {
  let cr = 0, lf = 0, crlf = 0;
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 13) cr++;
    if (bytes[i] === 10) {
      lf++;
      if (i > 0 && bytes[i - 1] === 13) crlf++;
    }
  }
  return { length: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), cr, lf, crlf,
    suffix: bytes.subarray(-2).equals(Buffer.from([13, 10])) ? 'CRLF' : bytes.at(-1) === 10 ? 'LF' : 'other' };
}
function nativeByteProbe() {
  const diagnosticBase = '189bafbd8818251fc6ef6c3d335bd08253c102d9';
  const directory = join(root, '.dev/headless-model-mck-evidence/native-windows-byte-probe');
  const executable = join(build, 'native/debug/build/finos/morphir-host/acceptance/protocol-fault/protocol-fault.exe');
  const cases = [
    { name: 'help', argv: ['--json', '--help'], expectedStatus: 0 },
    { name: 'syntax', argv: ['--json', '--'], expectedStatus: 1 },
  ];
  const started = process.hrtime.bigint();
  const elapsedMs = () => Number(process.hrtime.bigint() - started) / 1e6;
  const provenanceErrors: { operation: string; error: string }[] = [];
  const receipt: Record<string, unknown> = {
    purpose: 'diagnostic', strictLfQualification: 'unresolved', diagnosticBase,
    startedAt: new Date().toISOString(), platform: process.platform, arch: process.arch,
    osRelease: release(), osVersion: version(), node: process.version,
    github: Object.fromEntries(['GITHUB_SHA', 'GITHUB_WORKFLOW_REF', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_JOB',
      'RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion'].map(key => [key, process.env[key] ?? null])),
    build: { executable, target: 'native', mode: 'debug', directory: build,
      command: ['moon', 'build', '--target', 'native', 'pkgs/morphir-host/acceptance/protocol-fault'],
      execution: 'external prerequisite; this probe does not build', elapsedMs: null },
    capture: { shell: false, encoding: null, inputBytes: 0, timeout: 15000, maxBuffer: 24 * 1024 * 1024 },
    plannedCases: cases, cases: [], provenanceErrors, provenanceComplete: false, state: 'initializing',
  };
  mkdirSync(directory, { recursive: true });
  const save = () => writeFileSync(join(directory, 'receipt.json'), JSON.stringify({ ...receipt, elapsedMs: elapsedMs() }, null, 2) + '\n');
  save(); // Keep an initial receipt even if metadata or the requested binary fails.
  function metadata<T>(operation: string, collect: () => T): T | null {
    try { return collect(); }
    catch (error) { provenanceErrors.push({ operation, error: String(error) }); return null; }
  }
  function inspect(command: string, argv: string[]): Buffer {
    const result = spawnSync(command, argv, { cwd: root, env: environment, timeout: 15000, maxBuffer: 24 * 1024 * 1024 });
    if (result.error || result.status !== 0 || result.signal !== null) {
      throw new Error(`${command} ${argv.join(' ')}: ${String(result.error ?? result.status)}; signal=${result.signal}; ${result.stderr?.toString('utf8')}`);
    }
    return result.stdout;
  }
  receipt.checkout = metadata('git HEAD', () => inspect('git', ['rev-parse', 'HEAD']).toString('utf8').replace(/\r?\n$/, ''));
  const toolCommands: [string, string[]][] = [
    ['moon', ['version', '--all']], ['moonc', ['-v']], ['bun', ['--version']],
  ];
  receipt.toolchain = Object.fromEntries(toolCommands.map(([command, argv]) =>
    [command, metadata(`${command} version`, () => inspect(command, argv).toString('utf8'))]));
  const sources = [
    'pkgs/morphir-host/acceptance/protocol-fault/main.mbt',
    'pkgs/morphir-host/acceptance/protocol-fault/presentation.mbt',
    'pkgs/morphir-host/acceptance/protocol-fault/moon.pkg',
    'pkgs/morphir-host/moon.mod', 'pkgs/morphir-execution/moon.mod',
    'moon.mod', 'moon.work', '.config/mise/config.toml', 'tools/moonbit-core-pin.json',
    'apps/morphir/scripts/test-protocol-json-presentation.ts', '.github/workflows/headless-cli.yml',
  ];
  receipt.sources = sources.map(path => metadata(path, () => {
    const current = readFileSync(join(root, path));
    const original = inspect('git', ['show', `${diagnosticBase}:${path}`]);
    const committedBlob = inspect('git', ['rev-parse', `HEAD:${path}`]).toString('utf8').replace(/\r?\n$/, '');
    const baselineBlob = inspect('git', ['rev-parse', `${diagnosticBase}:${path}`]).toString('utf8').replace(/\r?\n$/, '');
    return { path, sha256: nativeByteSummary(current).sha256, committedBlob,
      committedUnchangedFromDiagnosticBase: committedBlob === baselineBlob,
      blob: createHash('sha1').update(`blob ${current.length}\0`).update(current).digest('hex'),
      diagnosticBaseBlob: inspect('git', ['rev-parse', `${diagnosticBase}:${path}`]).toString('utf8').replace(/\r?\n$/, ''),
      diagnosticBaseSha256: nativeByteSummary(original).sha256, unchangedFromDiagnosticBase: current.equals(original) };
  }));
  receipt.dependencies = ['.mooncakes/moonbitlang/x/moon.mod', '.mooncakes/moonrockz/ion/moon.mod'].map(path =>
    metadata(path, () => {
      const bytes = readFileSync(join(root, path));
      return { path, ...nativeByteSummary(bytes), blob: createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex') };
    }));
  receipt.corePin = metadata('core pin content', () => JSON.parse(readFileSync(join(root, 'tools/moonbit-core-pin.json'), 'utf8')) as unknown);
  receipt.executable = metadata('native executable hash', () => ({ path: executable, ...nativeByteSummary(readFileSync(executable)) }));
  receipt.provenanceComplete = provenanceErrors.length === 0;
  receipt.state = 'ready';
  save();
  const observations: Record<string, unknown>[] = [];
  receipt.cases = observations;
  try {
    context = { stage: 'native-byte-probe', executable, cwd: scratch };
    assert.ok(existsSync(executable), `Build requested native byte probe first: ${executable}`);
    for (const test of cases) {
      context = { stage: 'native-byte-probe', host: 'host.acceptance.protocol-fault', executable, argv: test.argv, cwd: scratch };
      const caseStarted = process.hrtime.bigint();
      const result = spawnSync(executable, test.argv, { cwd: scratch, env: environment, input: Buffer.alloc(0), timeout: 15000, maxBuffer: 24 * 1024 * 1024 });
      const caseElapsedMs = Number(process.hrtime.bigint() - caseStarted) / 1e6;
      // Persist the original Buffers before any process, framing or schema check.
      const stdout = result.stdout ?? Buffer.alloc(0), stderr = result.stderr ?? Buffer.alloc(0);
      writeFileSync(join(directory, `${test.name}.stdout.bin`), stdout);
      writeFileSync(join(directory, `${test.name}.stderr.bin`), stderr);
      const observation = { ...test, status: result.status, signal: result.signal,
        spawnError: result.error ? String(result.error) : null, elapsedMs: caseElapsedMs,
        stdout: nativeByteSummary(stdout), stderr: nativeByteSummary(stderr), cwdEntries: readdirSync(scratch), assertionsPassed: false };
      observations.push(observation);
      receipt.state = 'captured';
      save();
      assert.ifError(result.error);
      assert.equal(result.status, test.expectedStatus);
      assert.equal(result.signal, null);
      assert.equal(stderr.length, 0);
      assert.deepEqual(observation.cwdEntries, [], 'native help/refusal must not create cwd artifacts');
      const value = JSON.parse(stdout.toString('utf8')) as Record<string, unknown>;
      // Assert the compact body without asserting or normalizing its suffix.
      // JSON.parse above checks the untouched text, including trailing whitespace.
      const body = Buffer.from(JSON.stringify(value));
      assert.deepEqual(stdout.subarray(0, body.length), body, 'one compact JSON body');
      assert.equal(value.profile, 'morphir/command-result');
      assert.equal(value.contractVersion, '0.1.0');
      assert.equal(value.command, 'host.acceptance.protocol-fault');
      assert.equal(value.state, test.expectedStatus === 0 ? 'succeeded' : 'failed');
      assert.equal(value.exitCode, test.expectedStatus);
      assert.deepEqual(value.diagnostics, []);
      if (test.name === 'help') {
        assert.deepEqual(Object.keys(value).sort(), ['command', 'contractVersion', 'diagnostics', 'exitCode', 'profile', 'result', 'state']);
        const help = value.result as Record<string, unknown>;
        assert.deepEqual(Object.keys(help), ['render_help']);
        assert.equal(typeof help.render_help, 'string');
        assert.match(help.render_help as string, /host\.acceptance\.protocol-fault/);
        assert.match(help.render_help as string, /--json/);
      } else {
        assert.deepEqual(Object.keys(value).sort(), ['command', 'contractVersion', 'diagnostics', 'error', 'exitCode', 'profile', 'state']);
        const error = value.error as Record<string, unknown>;
        assert.deepEqual(Object.keys(error).sort(), ['code', 'message']);
        assert.equal(error.code, 'command.failed');
        assert.equal(typeof error.message, 'string');
        assert.match(error.message as string, /checkpoint/i);
      }
      observation.assertionsPassed = true;
      save();
    }
    receipt.state = 'observations-checked';
    save();
  } catch (error) {
    receipt.state = 'failed';
    receipt.failure = String(error);
    save();
    throw error;
  }
}
// Fixture-only experiment. It never changes the diagnostic probe or production hosts.
function nativeJsonBinaryModePrototype() {
  context = { stage: 'native-binary-mode-prototype' };
  const directory = join(root, '.dev/native-binary-stdout-prototype');
  mkdirSync(directory, { recursive: true });
  const started = process.hrtime.bigint();
  const commands: Record<string, unknown>[] = [];
  const checks: Record<string, unknown>[] = [];
  const sources: { path: string; sha256: string }[] = [];
  const receipt: Record<string, unknown> = {
    purpose: 'fixture-only prototype', state: 'initializing', startedAt: new Date().toISOString(),
    host: { platform: process.platform, arch: process.arch, release: release(), version: version(), node: process.version },
    windowsQualification: process.platform === 'win32' ? 'pending' : 'not-run-on-this-host',
    baseline: '8bc774022521f8422fb2f3d2632fa68f233e1a4d',
    capture: { shell: false, encoding: null, timeout: 30000, maxBuffer: 24 * 1024 * 1024 },
    references: {
      signature: 'https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/setmode?view=msvc-170',
      binaryConstant: 'https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/ucrt/fcntl.h',
      verifiedDefinition: '#define _O_BINARY 0x8000',
    }, commands, checks, sources,
  };
  const save = () => writeFileSync(join(directory, 'receipt.json'), JSON.stringify({ ...receipt,
    elapsedMs: Number(process.hrtime.bigint() - started) / 1e6 }, null, 2) + '\n');
  save();
  function capture(name: string, executable: string, argv: string[], cwd = directory) {
    assert.ok(Number(process.hrtime.bigint() - started) / 1e9 < 360, 'six-minute probe execution budget');
    const before = process.hrtime.bigint();
    const result = spawnSync(executable, argv, { cwd, env: environment, input: Buffer.alloc(0),
      timeout: 30000, maxBuffer: 24 * 1024 * 1024 });
    const stdout = result.stdout ?? Buffer.alloc(0), stderr = result.stderr ?? Buffer.alloc(0);
    writeFileSync(join(directory, `${name}.stdout.bin`), stdout);
    writeFileSync(join(directory, `${name}.stderr.bin`), stderr);
    commands.push({ name, executable, argv, cwd, elapsedMs: Number(process.hrtime.bigint() - before) / 1e6,
      status: result.status, signal: result.signal, error: result.error ? String(result.error) : null,
      stdout: { ...nativeByteSummary(stdout), hex: stdout.toString('hex'), base64: stdout.toString('base64') },
      stderr: { ...nativeByteSummary(stderr), hex: stderr.toString('hex'), base64: stderr.toString('base64') } });
    save(); // Original bytes survive even failed builds, launches or assertions.
    assert.ifError(result.error);
    assert.equal(result.signal, null);
    return { ...result, stdout, stderr };
  }
  function successful(name: string, executable: string, argv: string[], cwd = directory) {
    const result = capture(name, executable, argv, cwd);
    assert.equal(result.status, 0, `${name}: ${result.stderr.toString('utf8')}`);
    return result.stdout.toString('utf8');
  }
  function writeSource(path: string, content: string) {
    writeFileSync(path, content);
    sources.push({ path, sha256: createHash('sha256').update(content).digest('hex') });
    save();
  }
  function artifacts(path: string, suffix = '.exe'): string[] {
    return readdirSync(path, { withFileTypes: true }).flatMap(entry => {
      const child = join(path, entry.name);
      return entry.isDirectory() && !entry.name.endsWith('.dSYM') ? artifacts(child, suffix) : entry.isFile() && entry.name.endsWith(suffix) ? [child] : [];
    });
  }
  try {
    receipt.checkout = successful('head', 'git', ['rev-parse', 'HEAD'], root).trim();
    receipt.toolchain = successful('moon-version', 'moon', ['version', '--all']);
    receipt.compiler = successful('compiler-version', 'moonc', ['-v']);
    assert.match(String(receipt.toolchain), /2284bd2/);
    assert.match(String(receipt.compiler), /0\.10\.16\+b1a0e846e/);
    assert.equal(process.version, 'v24.22.0');
    receipt.runner = Object.fromEntries(['GITHUB_SHA', 'GITHUB_WORKFLOW_REF', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_JOB', 'RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion', 'VCToolsVersion', 'WindowsSDKVersion', 'UCRTVersion', 'UniversalCRTSdkDir', 'MOON_HOME'].map(key => [key, process.env[key] ?? null]));
    if (process.platform === 'win32') capture('compiler-location', 'where.exe', ['cl']);
    else capture('c-compiler-version', 'cc', ['--version']);
    for (const path of ['.github/workflows/headless-cli.yml', 'tools/moonbit-core-pin.json']) {
      sources.push({ path: join(root, path), sha256: createHash('sha256').update(readFileSync(join(root, path))).digest('hex') });
    }
    receipt.corePin = JSON.parse(readFileSync(join(root, 'tools/moonbit-core-pin.json'), 'utf8')) as unknown;
    receipt.driverSha256 = createHash('sha256').update(readFileSync(fileURLToPath(import.meta.url))).digest('hex');
    const core = join(process.env.MOON_HOME ?? '', 'lib/core');
    function coreFiles(path: string): string[] {
      return readdirSync(join(core, path), { withFileTypes: true }).flatMap(entry => {
        const relative = path ? `${path}/${entry.name}` : entry.name;
        return relative === '_build' ? [] : entry.isDirectory() ? coreFiles(relative) : [relative];
      });
    }
    const corePaths = coreFiles('').sort();
    const coreManifest = corePaths.map(path => `${path}\0${createHash('sha256').update(readFileSync(join(core, path))).digest('hex')}\n`).join('');
    const sourceSha256 = createHash('sha256').update(coreManifest).digest('hex');
    receipt.installedCore = { directory: core, sourceSha256, sourceFiles: corePaths.length };
    const pin = receipt.corePin as { sourceSha256: string; sourceFiles: number };
    assert.equal(sourceSha256, pin.sourceSha256, 'actual installed core matches pinned source identity');
    assert.equal(corePaths.length, pin.sourceFiles);
    const long = '界Ω😀'.repeat(8000);
    for (const delivery of ['standalone', 'package']) {
      for (const mode of ['text-help', 'json-help', 'text-refusal', 'json-refusal', 'injected-failure']) {
        const fixture = join(directory, delivery, mode);
        mkdirSync(fixture, { recursive: true });
        const candidate = mode.startsWith('json') || mode === 'injected-failure';
        const refusal = mode.endsWith('refusal');
        const marker = process.platform === 'win32' ? 'windows-native-selected' : 'windows-native-excluded';
        const value = {
          profile: 'morphir/command-result', contractVersion: '0.1.0', command: 'prototype.fixture',
          state: refusal ? 'failed' : 'succeeded', exitCode: refusal ? 1 : 0, diagnostics: [],
          ...(refusal ? { error: { code: 'command.failed', message: `checkpoint Ω ${long} MARKER` } }
            : { result: { render_help: `prototype.fixture --json Ω ${long} MARKER` } }),
        };
        const body = JSON.stringify(value);
        const source = `// Fixture only: stdout descriptor 1; never touches stderr, stdin or global fmode.
// _O_BINARY=0x8000 verified in Microsoft win32metadata UCRT fcntl.h.
#cfg(all(target="native", platform="windows"))
extern "C" fn setmode(fd : Int, mode : Int) -> Int = "_setmode"
#cfg(all(target="native", platform="windows"))
fn select_binary() -> Int { setmode(1, 0x8000) }
#cfg(not(all(target="native", platform="windows")))
fn select_binary() -> Int { 0 }
#cfg(all(target="native", platform="windows"))
fn adapter_marker() -> String { "windows-native-selected" }
#cfg(not(all(target="native", platform="windows")))
fn adapter_marker() -> String { "windows-native-excluded" }
#cfg(target="native")
extern "C" fn finish(status : Int) -> Unit = "exit"
#cfg(not(target="native"))
fn finish(_status : Int) -> Unit { () }
fn main {
  // Compile-time fixture variants each execute in a fresh process.
  let previous = ${mode === 'injected-failure' ? '-1 // Inject the return value, never an invalid descriptor.' : candidate ? 'select_binary()' : '0 // Default text variant NEVER calls select_binary().' }
  if previous < 0 {
    // Fail before stdout; do not claim a successful JSON response.
    finish(1)
  } else {
    let payload = ${JSON.stringify(body).replace('MARKER', '\\{adapter_marker()}')}
    println(payload)
    finish(${refusal ? 1 : 0})
  }
}
`;
        const sourcePath = join(fixture, delivery === 'standalone' ? 'fixture.mbtx' : 'main.mbt');
        writeSource(sourcePath, source);
        if (delivery === 'package') {
          writeSource(join(fixture, 'moon.mod'), 'name = "probe/binary-stdout"\nversion = "0.0.0"\n');
          writeSource(join(fixture, 'moon.pkg'), 'pkgtype(kind: "executable")\n');
        }
        const targets = mode === 'json-help' ? ['native', 'js', 'wasm', 'wasm-gc'] : ['native'];
        for (const target of targets) {
          const output = join(fixture, 'output', target);
          const name = `${delivery}-${mode}-${target}`;
          successful(`${name}-build`, 'moon', ['build', '--frozen', '-v', '--target', target, '--target-dir', output,
            delivery === 'standalone' ? sourcePath : '.'], fixture);
          checks.push({ name, compilation: 'passed', execution: target === 'native' ? 'pending' : 'not-run' });
          save();
          if (target !== 'native') {
            const emitted = artifacts(output, target === 'js' ? '.js' : '.wasm');
            assert.equal(emitted.length, 1, `${name}: unique emitted artifact`);
            for (const path of emitted) sources.push({ path, sha256: createHash('sha256').update(readFileSync(path)).digest('hex') });
            continue;
          }
          const binaries = artifacts(output);
          assert.equal(binaries.length, 1, `${name}: unique source-bound executable`);
          const binary = binaries[0]!;
          sources.push({ path: binary, sha256: createHash('sha256').update(readFileSync(binary)).digest('hex') });
          const observed = capture(`${name}-execute`, binary, [], fixture);
          assert.equal(observed.status, mode === 'injected-failure' || refusal ? 1 : 0);
          assert.equal(observed.stderr.length, 0);
          if (mode === 'injected-failure') assert.equal(observed.stdout.length, 0, 'mode failure suppresses stdout');
          else {
            const suffix = process.platform === 'win32' && !candidate ? '\r\n' : '\n';
            const expected = Buffer.from(body.replace('MARKER', marker) + suffix);
            assert.deepEqual(observed.stdout, expected, 'exact compact UTF-8, selection marker, suffix, no BOM');
            assert.ok(expected.length > 65536, 'exercise multiple println encoding chunks');
            assert.deepEqual(JSON.parse(observed.stdout.toString('utf8')), JSON.parse(body.replace('MARKER', marker)));
          }
          checks[checks.length - 1]!.execution = 'passed';
          save();
        }
      }
    }
    receipt.windowsQualification = process.platform === 'win32' ? 'fixture-controls-passed' : 'not-run-on-this-host';
    receipt.state = 'passed';
    save();
    console.log(JSON.stringify({ prototype: 'passed', receipt: join(directory, 'receipt.json'), checks }));
  } catch (error) {
    receipt.state = 'failed';
    receipt.failure = String(error);
    save();
    throw error;
  }
}
async function main() {
  if (process.env.NATIVE_JSON_BINARY_MODE_PROTOTYPE === '1') {
    nativeJsonBinaryModePrototype();
    return;
  }
  if (process.env.PROTOCOL_JSON_NATIVE_BYTE_PROBE === '1') nativeByteProbe();
  for (const host of hosts) {
    context = { stage: 'artifact', host: host.name, argv: [host.artifact] };
    assert.ok(existsSync(host.artifact), `Build current artifact first: ${host.artifact}`);
    let assertions = 0;
    const observations: Receipt['cases'] = [];
    const summarize = (value: ReturnType<typeof run>): Observation => ({ status: value.status, signal: value.signal, stdoutBytes: value.stdout.length, stdoutSha256: createHash('sha256').update(value.stdout).digest('hex'), stderrBytes: value.stderr.length });
    const bad = host.budget ? Buffer.from('incomplete') : Buffer.from('Content-Length: 8\r\n\r\nx');
    const cases = [Buffer.alloc(0), host.input, bad];
    if (host.budget) cases.push(Buffer.from("{\n"));
    if (host.budget) cases.push(Buffer.from([0xff, 10]), Buffer.from('x'.repeat(host.budget + 1)));
    for (const [caseIndex, input] of cases.entries()) {
      context = { stage: 'protocol-case', host: host.name, case: caseIndex };
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
    context = { stage: 'help', host: host.name };
    await noEffectsHelp(host);
    assertions++;
    context = { stage: 'invalid-option', host: host.name };
    const invalid = run(host, ['--json', '--unknown'], host.input);
    assert.equal(invalid.status, 2);
    assert.equal(invalid.stdout.length, 0);
    const invalidRows = events(host, invalid.stderr);
    assert.equal(invalidRows[0]?.event, 'failure');
    assertions++;
    context = { stage: 'large-diagnostic', host: host.name };
    const largeDiagnostic = host.node
      ? await largeSyntaxDiagnostic(host, (invalidRows[0]?.error as { message: string }).message)
      : undefined;
    if (largeDiagnostic) assertions++;
    if (host.budget) {
      for (const args of [['--forward-argv', '--', '--json', '', 'Ω', '--', '--help'], ['ignored', '', 'Ω', '--', '--json']]) {
        context = { stage: 'forward-argv', host: host.name };
        const literal = run(host, args, host.input);
        const ordinary = run(host, [], host.input);
        assert.deepEqual(literal.stdout, ordinary.stdout);
        assert.deepEqual(literal.stderr, ordinary.stderr);
        assert.equal(literal.status, ordinary.status);
        assertions++;
      }
      context = { stage: 'opaque-argv', host: host.name };
      const opaque = run(host, ['--json', '--', '', 'Ω', '--', '--json', '--help'], host.input);
      assert.equal(opaque.status, 0);
      assert.deepEqual(opaque.stdout, run(host, [], host.input).stdout);
      assert.equal(events(host, opaque.stderr).at(-1)?.event, 'exit');
      assertions++;
    } else {
      context = { stage: 'legacy-help', host: host.name };
      const legacy = run(host, ['--help'], host.input);
      assert.equal(legacy.status, 2);
      assert.equal(legacy.stdout.length, 0);
      assertions++;
    }
    context = { stage: 'default-failure', host: host.name };
    const failure = run(host, [], bad);
    receipts.push({ host: host.name, largeDiagnostic, assertions, cases: observations, defaultFailure: { status: failure.status, signal: failure.signal } });
  }
  context = { stage: 'cwd-check', cwd: scratch };
  assert.deepEqual(readdirSync(scratch), [], 'help and protocol processes must not create cwd artifacts');
  // Exercise the exact current pure event adapter and its permanent fixtures,
  // without importing Proton, linking CEF or launching an application window.
  const fixture = join(scratch, 'desktop-pure');
  context = { stage: 'pure-setup', cwd: fixture };
  mkdirSync(fixture);
  writeFileSync(join(fixture, 'moon.mod'), 'name = "presentation-fixture"\nversion = "0.0.0"\n');
  writeFileSync(join(fixture, 'moon.pkg'), 'import { "moonbitlang/core/argparse", "moonbitlang/core/json", }\n');
  for (const file of ['json_presentation.mbt', 'json_presentation_wbtest.mbt']) {
    writeFileSync(join(fixture, file), readFileSync(join(root, 'apps/morphir-workbench-desktop/app', file)));
  }
  for (const target of ['native', 'js', 'wasm', 'wasm-gc']) {
    context = { stage: 'pure-test', target, executable: 'moon', argv: ['test', '--target', target], cwd: fixture };
    const tested = spawnSync('moon', ['test', '--target', target], { cwd: fixture, env: environment, encoding: 'utf8', timeout: 30000 });
    if (tested.error) console.error('Pure desktop fixture output', tested.stdout, tested.stderr);
    assert.ifError(tested.error);
    assert.equal(tested.status, 0, `${target} pure desktop fixtures: ${tested.stdout}${tested.stderr}`);
  }
  context = { stage: 'receipt' };
  const result = { host: `${process.platform}/${process.arch}`, node: process.version, baselineCompared: Boolean(baseline), desktopPureFixtureTargets: ['native', 'js', 'wasm', 'wasm-gc'], receipts };
  if (process.env.PROTOCOL_JSON_RECEIPT) writeFileSync(process.env.PROTOCOL_JSON_RECEIPT, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({ ...result, receipts: receipts.map(({ cases: _cases, ...receipt }) => receipt) }));
}
try {
  await main();
} catch (error) {
  failure = { error };
  console.error('Protocol JSON presentation failed', JSON.stringify(context), error);
  throw error;
} finally {
  try { rmSync(scratch, { recursive: true, force: true }); }
  catch (cleanupError) {
    if (failure) throw new AggregateError([failure.error, cleanupError], `Protocol JSON presentation failed and scratch cleanup failed: ${scratch}`, { cause: failure.error });
    throw cleanupError;
  }
}
