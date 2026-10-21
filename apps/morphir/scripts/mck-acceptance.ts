import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as pause } from 'node:timers/promises';

interface Invocation { command: string; prefix: string[] }
interface RecordView { caseId: string; result: string; [key: string]: unknown }
interface Report { records: RecordView[]; [key: string]: unknown }
const app = fileURLToPath(new URL('../', import.meta.url));
const hash = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');

/** Qualified command delegation, not an implementation conformance claim. All
 * kit bytes, transcripts and expected reports come from the canonical parent. */
export function exerciseMck(invocation: Invocation, directory: string, pinPath: string, source: string, helper: string) {
  mkdirSync(directory, { recursive: true });
  const pin = JSON.parse(readFileSync(pinPath, 'utf8'));
  assert.equal(hash(pin.executable), pin.sha256);
  const originalPin = hash(pinPath);
  const fixtureRevision = process.env.MORPHIR_MCK_FIXTURE_REVISION;
  const verifyFixtures = () => {
    if (process.env.MORPHIR_MCK_REQUIRED !== '1') return;
    assert.match(fixtureRevision ?? '', /^[a-f0-9]{40}$/);
    const git = (args: string[]) => execFileSync('git', ['-C', source, ...args], { encoding: 'utf8', timeout: 10000 }).trim();
    assert.equal(git(['rev-parse', 'HEAD']), fixtureRevision, 'Exact canonical fixture commit required');
    assert.equal(git(['status', '--porcelain', '--untracked-files=all', '--', 'spec']), '', 'Canonical fixture inputs changed');
  };
  verifyFixtures();
  const home = join(directory, 'home'); mkdirSync(home);
  const env: NodeJS.ProcessEnv = {
    PATH: '', HOME: home, USERPROFILE: home, LOCALAPPDATA: home, APPDATA: home,
    XDG_CACHE_HOME: home, TMPDIR: home, TMP: home, TEMP: home,
    MORPHIR_LOG_FILE: 'false', MORPHIR_NO_BANNER: '1',
    ...(process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}),
  };
  const receipts: { args: string[]; exitCode: number; stdout: string; stderr: string }[] = [];
  const execute = (command: string, args: string[]) => {
    const result = spawnSync(command, args, { cwd: directory, env, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024 });
    assert.equal(result.error, undefined, `${command}: ${result.error}`);
    assert.equal(result.signal, null, result.stderr); assert.notEqual(result.status, null);
    return { exitCode: result.status!, stdout: result.stdout, stderr: result.stderr };
  };
  const run = (args: string[], expected = 0) => {
    const result = execute(invocation.command, [...invocation.prefix, 'mck', '--runner-pin', pinPath,
      '--mck-helper', helper, '--node', process.execPath, ...args]);
    assert.equal(result.exitCode, expected, `${args.join(' ')}\n${result.stdout}\n${result.stderr}`);
    receipts.push({ args, ...result }); return result;
  };
  const parity = (args: string[], expected = 0) => {
    const direct = execute(pin.executable, ['--no-banner', 'mck', ...args]);
    const delegated = run(args, expected);
    // The parent assigns a fresh correlation ID to each failed invocation.
    const stable = (result: typeof direct) => ({ ...result,
      stderr: result.stderr.replace(/^Operation ID: op-[a-f0-9-]+$/gm, 'Operation ID: <per-invocation>') });
    assert.deepEqual(stable(delegated), stable(direct), 'Delegation changed canonical result/output');
    return delegated;
  };
  const embedded = JSON.parse(parity(['kit', 'status', '--json']).stdout);
  assert.equal(embedded.revision, pin.sourceRevision);
  assert.match(embedded.corpusHash, /^sha256-[a-f0-9]{64}$/);
  const kit = join(directory, 'kit');
  run(['kit', 'vendor', '--source', 'embedded', '--dest', kit, '--json']);
  const status = JSON.parse(parity(['kit', 'status', '--kit', kit, '--json']).stdout);
  assert.equal(status.corpusHash, embedded.corpusHash);
  parity(['check', kit, '--json']);
  parity(['coverage', '--kit', kit]);
  parity(['schema', 'check', '--kit', kit]);
  run(['kit', 'update', '--kit', kit, '--source', 'embedded', '--json']);
  const feature = readdirSync(join(kit, 'spec/ir/mck')).find(name => name.endsWith('.feature'))!;
  assert.ok(feature);
  const featurePath = join(kit, 'spec/ir/mck', feature), featureBytes = readFileSync(featurePath);
  const lockBefore = readFileSync(join(kit, 'mck-kit.lock.json'));
  writeFileSync(featurePath, Buffer.concat([featureBytes, Buffer.from('\n# altered vendored input\n')]));
  parity(['check', kit, '--json'], 1);
  run(['kit', 'update', '--kit', kit, '--source', 'embedded'], 1);
  assert.deepEqual(readFileSync(join(kit, 'mck-kit.lock.json')), lockBefore);
  writeFileSync(featurePath, featureBytes);
  const invalid = join(directory, 'invalid-schema'); cpSync(kit, invalid, { recursive: true });
  rmSync(join(invalid, 'mck-kit.lock.json'));
  writeFileSync(join(invalid, 'spec/ir/mck/protocol.schema.json'), '{"type":"not-a-schema-type"}');
  parity(['schema', 'check', '--kit', join(invalid, 'spec/ir/mck'), '--repo-root', invalid], 1);

  const adapter = join(app, 'scripts/mck-fixture-adapter.ts');
  const ir = join(source, 'spec/mck/baseline/kit-2026-09-26');
  const frozenReport = join(source, 'spec/mck/baseline/reports/morphir-typescript.json');
  const expected = JSON.parse(readFileSync(frozenReport, 'utf8')) as Report;
  const ids = [...new Set(expected.records.map(row => row.caseId))].sort();
  const filter = `^(?:${ids.join('|')})$`;
  const transcript = join(source, 'spec/mck/baseline/transcripts/morphir-typescript.ndjson');
  const baseArgs = ['run', '--kit', ir, '--filter', filter, '--adapter', process.execPath,
    '--adapter-arg', adapter, '--adapter-arg', 'replay', '--adapter-arg', transcript];
  const allowed = join(directory, 'allowed.json'); writeFileSync(allowed, '{"cases":[]}');
  const report = join(directory, 'ir.json'); run([...baseArgs, '--report', report]);
  const actual = JSON.parse(readFileSync(report, 'utf8')) as Report;
  assert.equal(actual.records.length, expected.records.length);
  const verdicts = (value: Report) => value.records.map(({ durationMs: _duration, ...row }) => row);
  assert.deepEqual(verdicts(actual), verdicts(expected), 'Canonical per-case verdicts and skipped semantics changed');
  run(['report', 'check', report, allowed, '--kit', ir, '--filter', filter]);
  parity(['report', 'compare', report, report]);
  const second = join(directory, 'second.json'); run([...baseArgs, '--report', second]);
  run(['report', 'compare', report, second]);
  const html = join(directory, 'report.html'); run(['report', 'render', report, '--format', 'html', '--output', html]);
  assert.match(readFileSync(html, 'utf8'), /<!doctype html>/i);
  const truncated = structuredClone(actual); truncated.records.pop();
  const badReport = join(directory, 'truncated.json'); writeFileSync(badReport, JSON.stringify(truncated));
  run(['report', 'check', badReport, allowed, '--kit', ir, '--filter', filter], 1);
  run(['report', 'compare', report, badReport], 1);
  const failing = join(directory, 'failing.json');
  run([...baseArgs, '--adapter-arg', 'fail', '--report', failing], 1);
  const failed = JSON.parse(readFileSync(failing, 'utf8')) as Report;
  assert.deepEqual([...new Set(failed.records.filter(row => row.result === 'fail').map(row => row.caseId))], [expected.records[0]!.caseId]);
  const developmentBaseline = join(directory, 'development-baseline.json');
  writeFileSync(developmentBaseline, JSON.stringify({ cases: [expected.records[0]!.caseId] }));
  run(['report', 'check', failing, developmentBaseline, '--kit', ir, '--filter', filter]);
  const partial = join(directory, 'partial.json');
  run([...baseArgs, '--adapter-arg', 'partial', '--report', partial], 1);
  run(['report', 'check', partial, allowed, '--kit', ir, '--filter', filter], 1);
  // The runner independently selects its corpus; a report cannot choose a new kit.
  run(['report', 'check', report, allowed, '--kit', kit, '--filter', filter], 1);

  for (const [suite, contract] of [['integrity', '0.1.0-draft.1'], ['resolution', '0.1.0-draft.2']]) {
    const saved = join(directory, `package-${suite}.json`);
    run(['package', 'run', '--contract', contract!, '--kit', join(source, 'spec/package/mck'),
      '--adapter', process.execPath, '--adapter-arg', adapter, '--adapter-arg', 'replay',
      '--adapter-arg', join(source, `spec/mck/baseline/package/${suite}.ndjson`), '--report', saved]);
    const expectedPackage = JSON.parse(readFileSync(join(source, `spec/mck/baseline/package/${suite}.json`), 'utf8'));
    const observed = JSON.parse(readFileSync(saved, 'utf8'));
    for (const value of [expectedPackage, observed]) { delete value.driverVersion; delete value.startedAt; }
    assert.deepEqual(observed, expectedPackage, 'Package records differ from canonical frozen evidence');
  }
  run(['package', 'inspect', '--source', source, '--contract', '0.1.0-draft.3']);
  const nodeKit = join(source, 'spec/ir/mck/node-address-draft.json');
  const nodeReport = join(directory, 'node-address.json');
  run(['node-address', 'run', '--kit', nodeKit, '--adapter', process.execPath,
    '--adapter-arg', adapter, '--adapter-arg', 'node-address', '--adapter-arg', nodeKit, '--report', nodeReport]);
  const nodes = JSON.parse(readFileSync(nodeReport, 'utf8'));
  assert.equal(nodes.records.length, JSON.parse(readFileSync(nodeKit, 'utf8')).cases.length);
  assert.ok(nodes.records.every((row: RecordView) => row.result === 'pass'));
  assert.equal(hash(pinPath), originalPin); assert.equal(hash(pin.executable), pin.sha256);
  verifyFixtures();
  writeFileSync(join(directory, 'receipt.json'), JSON.stringify({
    kind: 'canonical-mck-cli-delegation', runner: pin, embeddedKit: embedded,
    source, fixtureRevision: fixtureRevision ?? null,
    adapterSha256: hash(adapter), irCorpusRecords: actual.records.length,
    fixtures: [frozenReport, transcript, join(source, 'spec/ir/mck/node-address-draft.json'),
      ...['integrity', 'resolution'].flatMap(suite => [join(source, `spec/mck/baseline/package/${suite}.ndjson`), join(source, `spec/mck/baseline/package/${suite}.json`)])]
      .map(path => ({ path, sha256: hash(path) })),
    nodeAddressRecords: nodes.records.length, packageContracts: ['0.1.0-draft.1', '0.1.0-draft.2', '0.1.0-draft.3'],
    path: env.PATH, toolchainAcquisition: false, cases: receipts,
  }, null, 2) + '\n');
  console.log(`MCK CLI delegation: inspection, managed kits, IR reports, package and node-address passed with PATH empty.`);
}

/** Exercise the canonical runner's own separately grouped adapter, not a fake
 * child sharing the runner group. A cancelled report cannot pass its checker. */
export async function exerciseMckCancellation(invocation: Invocation, directory: string, pinPath: string, source: string, helper: string) {
  mkdirSync(directory, { recursive: true });
  const adapter = join(app, 'scripts/mck-fixture-adapter.ts');
  const transcript = join(source, 'spec/mck/baseline/transcripts/morphir-typescript.ndjson');
  const kit = join(source, 'spec/mck/baseline/kit-2026-09-26');
  const phases = [];
  const pin = JSON.parse(readFileSync(pinPath, 'utf8'));
  // Node's Windows child.kill('SIGINT') terminates a process rather than
  // generating a console Ctrl-C event. Qualify that signal path on POSIX only.
  const mechanisms = process.platform === 'win32' ? ['file', 'deadline'] : ['file', 'signal', 'deadline'];
  for (const mechanism of mechanisms) {
    const root = join(directory, mechanism); mkdirSync(root);
    const cancelFile = join(root, 'cancel'), witness = join(root, 'adapter.json'), report = join(root, 'report.json');
    const env = { PATH: '', HOME: root, USERPROFILE: root, TMPDIR: root, TMP: root, TEMP: root, MORPHIR_LOG_FILE: 'false',
      ...(process.env.SystemRoot ? { SystemRoot: process.env.SystemRoot } : {}) };
    const timeout = mechanism === 'deadline' ? process.platform === 'win32' ? 15000 : 5000 : 30000;
    const args = [...invocation.prefix, '--json', 'mck', '--runner-pin', pinPath, '--mck-helper', helper,
      '--node', process.execPath, '--timeout', String(timeout), '--cancel-file', cancelFile,
      'run', '--kit', kit, '--filter', '^definitions-0001$', '--report', report,
      '--adapter', process.execPath, '--adapter-arg', adapter, '--adapter-arg', 'replay', '--adapter-arg', transcript,
      '--adapter-arg', 'hang', '--adapter-arg', witness];
    const child = spawn(invocation.command, args, { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += String(data); });
    child.stderr.on('data', data => { stderr += String(data); });
    let status: { code: number | null; signal: NodeJS.Signals | null } | undefined;
    const exited = new Promise<void>((resolve, reject) => {
      child.once('error', reject); child.once('close', (code, signal) => { status = { code, signal }; resolve(); });
    });
    try {
      const limit = performance.now() + 25000;
      while (!existsSync(witness) && performance.now() < limit && !status) await pause(10);
      assert.ok(existsSync(witness), `Real adapter did not start: ${stdout}\n${stderr}`);
      const { pid } = JSON.parse(readFileSync(witness, 'utf8')) as { pid: number };
      assert.ok(Number.isSafeInteger(pid) && pid > 0); process.kill(pid, 0);
      if (mechanism === 'file') writeFileSync(cancelFile, '');
      if (mechanism === 'signal') child.kill('SIGINT');
      let timer: ReturnType<typeof setTimeout> | undefined;
      try { await Promise.race([exited, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(Error('MCK cancellation did not finish')), 25000); })]); }
      finally { clearTimeout(timer); }
      assert.deepEqual(status, { code: mechanism === 'deadline' ? 124 : 130, signal: null }, stdout + stderr);
      const receipt = JSON.parse(stdout);
      assert.equal(receipt.state, mechanism === 'deadline' ? 'failed' : 'cancelled');
      assert.doesNotMatch(receipt.error, /tree_termination_unconfirmed|tree_termination_failed/);
      assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' }, 'The canonical adapter must be gone before cancellation returns');
      const baseline = join(root, 'baseline.json'); writeFileSync(baseline, '{"cases":[]}');
      const check = spawnSync(pin.executable, ['--no-banner', 'mck', 'report', 'check', report, baseline,
        '--kit', kit, '--filter', '^definitions-0001$'], { cwd: root, env, encoding: 'utf8', timeout: 10000 });
      assert.equal(check.error, undefined); assert.equal(check.signal, null);
      assert.equal(check.status, 1, 'Cancelled output must not qualify as a complete report');
      phases.push({ mechanism, adapterPid: pid, ...status, receipt, adapterRemoved: true,
        reportRefusal: { exitCode: check.status, stdout: check.stdout, stderr: check.stderr } });
    } finally {
      if (!status) { child.kill('SIGINT'); await Promise.race([exited, pause(6000)]); }
      if (!status) child.kill('SIGKILL');
    }
  }
  writeFileSync(join(directory, 'receipt.json'), JSON.stringify({ kind: 'canonical-mck-cancellation', phases }, null, 2) + '\n');
  console.log(`MCK CLI cancellation: ${mechanisms.join(', ')} reclaimed actual canonical adapter processes.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const command = JSON.parse(process.env.MORPHIR_MCK_COMMAND ?? 'null') as string[] | null;
  assert.ok(command?.length && process.env.MORPHIR_MCK_PIN && process.env.MORPHIR_MCK_SOURCE && process.env.MORPHIR_MCK_HELPER,
    'Set explicit MORPHIR_MCK_COMMAND JSON argv, MORPHIR_MCK_PIN, MORPHIR_MCK_SOURCE and MORPHIR_MCK_HELPER');
  const directory = resolve(process.env.MORPHIR_MCK_EVIDENCE ?? '.dev/mck-command-acceptance');
  assert.equal(existsSync(directory), false, 'Use a fresh evidence directory');
  exerciseMck({ command: command[0]!, prefix: command.slice(1) }, directory,
    resolve(process.env.MORPHIR_MCK_PIN), resolve(process.env.MORPHIR_MCK_SOURCE), resolve(process.env.MORPHIR_MCK_HELPER));
  await exerciseMckCancellation({ command: command[0]!, prefix: command.slice(1) }, join(directory, 'cancellation'),
    resolve(process.env.MORPHIR_MCK_PIN), resolve(process.env.MORPHIR_MCK_SOURCE), resolve(process.env.MORPHIR_MCK_HELPER));
}
