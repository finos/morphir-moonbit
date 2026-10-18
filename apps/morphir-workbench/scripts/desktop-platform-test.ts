import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createReadStream } from 'node:fs';
import { access, lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { createServer as httpServer } from 'node:http';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { chromium, type Browser, type Page } from 'playwright';
import { supervised } from '../../morphir/build-provider/supervision.mjs';
import type { CoreReply, NativeDescriptor, NativeReply } from '../browser/contracts.ts';
import type { CodeEditor } from '../browser/editor/code-editor.ts';

// This application acceptance owns its real package fixture through the same
// process-group/Windows Job supervisor qualified by the installed CLI tests.
// Target selection, builds and the matrix gate remain MoonBit task commands.
type Target = 'linux-x64' | 'windows-x64';
type EmptyDescriptor = Pick<NativeDescriptor, 'profile' | 'contractVersion' | 'sessionId' | 'operations'>;
type ProbeWindow = Window & { platformProbe: { completed: Record<string, number>; native: string[] } };
const target = process.argv[2];
assert.ok(target === 'linux-x64' || target === 'windows-x64', 'Select linux-x64 or windows-x64');
assert.equal(`${process.platform}:${process.arch}`, target === 'linux-x64' ? 'linux:x64' : 'win32:x64', 'Use the actual selected host');
const evidence = resolve(process.argv[3] ?? `.dev/packaged-targets/${target}`);
const build: unknown = JSON.parse(await readFile(join(evidence, 'build.json'), 'utf8'));
assert.ok(build && typeof build === 'object' && 'target' in build && build.target === target && 'status' in build && build.status === 'built');
await assert.rejects(access(join(evidence, 'acceptance.json')), 'Never replace a previous acceptance receipt');
const packageRoot = await realpath(join(evidence, 'package'));
const entry = target === 'linux-x64' ? join(packageRoot, 'morphir-workbench-0.1.0-x86_64.AppImage')
  : join(packageRoot, 'morphir-workbench', 'morphir-workbench.exe');
assert.equal((await lstat(entry)).isFile(), true);
const executable = await open(entry, 'r');
const header = Buffer.alloc(128);
try { assert.equal((await executable.read(header, 0, header.length, 0)).bytesRead, header.length); }
finally { await executable.close(); }
if (target === 'linux-x64') {
  assert.equal(header.subarray(0, 4).toString('hex'), '7f454c46');
  assert.equal(header.readUInt16LE(18), 62, 'The AppImage is x86-64');
  assert.equal(header.subarray(8, 11).toString('hex'), '414902', 'Launch the type-2 AppImage entry');
} else {
  assert.equal(header.subarray(0, 2).toString(), 'MZ');
  const helper = await readFile(join(packageRoot, 'morphir-workbench', 'cef_process.exe'));
  assert.equal(helper.readUInt16LE(helper.readUInt32LE(0x3c) + 92), 2, 'The real packaged CEF helper uses the Windows GUI subsystem');
}

async function digest(path: string) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
async function inventory(root: string, prefix = ''): Promise<{ path: string; sha256: string }[]> {
  const result: { path: string; sha256: string }[] = [];
  for (const name of (await readdir(join(root, prefix))).sort()) {
    const path = prefix ? `${prefix}/${name}` : name;
    const stat = await lstat(join(root, path));
    assert.equal(stat.isSymbolicLink(), false, 'Portable package inventory contains no links');
    if (stat.isDirectory()) result.push(...await inventory(root, path));
    else { assert.ok(stat.isFile()); result.push({ path, sha256: await digest(join(root, path)) }); }
  }
  return result;
}
const files = await inventory(packageRoot);
const reservation = createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
const address = reservation.address(); assert.ok(address && typeof address !== 'string');
const port = address.port;
await new Promise<void>(resolve => reservation.close(() => resolve()));
const scratch = await mkdtemp(join(tmpdir(), 'morphir-packaged-fallback-'));
const profileRoot = join(scratch, 'temporary'); await mkdir(profileRoot);
const cancelFile = join(scratch, 'cancel');
const env: NodeJS.ProcessEnv = { ...process.env };
for (const key of Object.keys(env)) if (/^(PROTON_|CEF_|MORPHIR_|DYLD_)/i.test(key) || ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'NODE_OPTIONS'].includes(key)) delete env[key];
Object.assign(env, { PROTON_HEADLESS: '1', PROTON_REMOTE_DEBUGGING_PORT: String(port), TMPDIR: profileRoot, TEMP: profileRoot, TMP: profileRoot });
if (target === 'windows-x64') env.ANGLE_DEFAULT_PLATFORM = 'swiftshader';
const args = target === 'linux-x64' ? ['--appimage-extract-and-run'] : [];
let quiescent = false, forcedCleanup = false;
const exit = supervised(entry, args, { cwd: packageRoot, env, timeout: 600000, cancelFile }).then(result => {
  quiescent = true;
  return { kind: 'exit' as const, result };
}, (error: unknown) => {
  const message = String(error);
  quiescent = !message.includes('execution.tree_termination_failed');
  return { kind: 'error' as const, message };
});
let exited = false; void exit.then(() => { exited = true; });
let browser: Browser | undefined;
const checks: string[] = [], errors: string[] = [];
let workersStarted = 0, workersClosed = 0;
let profiles: string[] = [];
const until = async (condition: () => Promise<boolean>, milliseconds = 30000) => {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) { if (await condition()) return; await pause(50); }
  throw new Error('Packaged acceptance condition timed out');
};
const paint = (page: Page) => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
async function probe(page: Page) {
  await page.evaluate(() => {
    const state = { completed: {} as Record<string, number>, native: [] as string[] };
    (window as unknown as ProbeWindow).platformProbe = state;
    const request = globalThis.morphirWorkbench.request.bind(globalThis.morphirWorkbench);
    globalThis.morphirWorkbench.request = (data, receive) => request(data, source => {
      state.completed[data.operation] = (state.completed[data.operation] ?? 0) + 1; receive(source);
    });
    const bridge = window.__MoonBit__!.core!;
    const invoke = bridge.invokeOp!.bind(bridge);
    bridge.invokeOp = (operation, source) => {
      if (operation === 'app:workbench_native') state.native.push(source);
      return invoke(operation, source);
    };
  });
}
async function complete(page: Page, operation: string, action: () => Promise<unknown>) {
  const before = await page.evaluate(operation => (window as unknown as ProbeWindow).platformProbe.completed[operation] ?? 0, operation);
  await action();
  await page.waitForFunction(({ operation, before }) => ((window as unknown as ProbeWindow).platformProbe.completed[operation] ?? 0) > before, { operation, before });
  await paint(page);
}
async function native<T>(page: Page, operation: string, sessionId: string | null = null, payload?: unknown): Promise<NativeReply<T>> {
  return page.evaluate(async ({ operation, sessionId, payload }) => {
    const source = JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation,
      ...(sessionId === null ? {} : { sessionId }), ...(payload === undefined ? {} : { payload }) });
    const raw = await window.__MoonBit__!.core!.invokeOp!('app:workbench_native', source);
    const checked: CoreReply<NativeReply<T>> = JSON.parse(globalThis.morphirWorkbenchExecutions(JSON.stringify({
      op: 'native-policy-response', source: raw, operation, sessionId,
    })));
    if (!checked.ok) throw new Error(`Native reply failed the production codec: ${checked.code}`);
    return checked.value;
  }, { operation, sessionId, payload });
}
function value<T>(reply: NativeReply<T>): T { assert.ok(reply.ok, JSON.stringify(reply)); return reply.value; }
function denied(reply: NativeReply<unknown>, code: string) { assert.ok(!reply.ok); assert.equal(reply.error.code, code, JSON.stringify(reply)); assert.equal(reply.error.effect, 'none'); }
function empty(descriptor: EmptyDescriptor) {
  assert.deepEqual(Object.keys(descriptor).sort(), ['contractVersion', 'operations', 'profile', 'sessionId']);
  assert.equal(descriptor.profile, 'morphir/workbench/native'); assert.equal(descriptor.contractVersion, '0.2.0-draft.2');
  assert.deepEqual(descriptor.operations, []); assert.ok(descriptor.sessionId.length > 0);
}
async function workerWorkflow(page: Page, mode: 'native-fallback' | 'standalone') {
  await probe(page);
  await page.getByRole('button', { name: 'Try Morphir', exact: true }).click(); await paint(page);
  const source = page.getByRole('textbox', { name: 'Source editor', exact: true });
  await source.fill('(+ 20 22)'); await paint(page);
  assert.equal(await page.locator('#source').evaluate(e => (e as CodeEditor).value), '(+ 20 22)');
  await complete(page, 'compile', () => page.getByRole('button', { name: 'Compile & run', exact: true }).click());
  await page.waitForFunction(() => document.querySelector('.run-value strong')?.textContent === '42');
  await page.getByRole('button', { name: 'Model Explorer', exact: true }).click(); await paint(page);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import model', exact: true }).first().click();
  await complete(page, 'inspect', async () => (await chooser).setFiles(fileURLToPath(new URL('../fixtures/typed-pricing.json', import.meta.url))));
  await page.getByRole('status').filter({ hasText: 'Model ready' }).waitFor();
  await page.locator('.tree-item[title="pricing:quotes#total"]').click();
  await page.getByRole('button', { name: 'Typed invocation', exact: true }).click(); await paint(page);
  const policy = page.getByRole('combobox', { name: 'Capability checks', exact: true });
  if (mode === 'native-fallback' && await policy.count()) {
    assert.equal(await policy.inputValue(), 'strict');
    assert.equal(await policy.locator('option[value="permissive"]').evaluate(e => (e as HTMLOptionElement).disabled), true);
  }
  const workspace = page.getByRole('button', { name: 'Open workspace', exact: true });
  assert.ok(await workspace.count() === 0 || await workspace.isDisabled(), 'Fallback must not offer a workspace grant');
  const evaluate = async () => {
    await complete(page, 'evaluate', () => page.getByRole('button', { name: 'Evaluate', exact: true }).click());
    await page.getByRole('status').filter({ hasText: 'Function evaluated' }).waitFor();
    const json = page.getByRole('button', { name: 'Result JSON', exact: true });
    await json.click(); await paint(page);
    assert.deepEqual(JSON.parse(await page.locator('#evaluation-output').evaluate(e => (e as CodeEditor).value)), { type: 'decimal', coefficient: '375', exponent: -1 });
  };
  await page.getByRole('textbox', { name: 'quote.price.coefficient', exact: true }).fill('125');
  await page.getByRole('textbox', { name: 'quote.price.exponent', exact: true }).fill('-1');
  await page.getByRole('textbox', { name: 'quote.quantity', exact: true }).fill('3'); await paint(page);
  await evaluate();
  const argumentsText = '[{"type":"record","fields":[{"name":"price","value":{"type":"decimal","coefficient":"125","exponent":-1}},{"name":"quantity","value":{"type":"int","value":"3"}}]}]';
  await page.getByRole('button', { name: 'JSON inputs', exact: true }).click(); await paint(page);
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill(argumentsText); await paint(page); await evaluate();
  await page.getByRole('button', { name: 'Ion inputs', exact: true }).click(); await paint(page);
  await page.getByRole('textbox', { name: 'Function arguments', exact: true }).fill('[morphir_value::{type:"record",fields:[{name:"price",value:{type:"decimal",coefficient:"125",exponent:-1}},{name:"quantity",value:{type:"int",value:"3"}}]}]');
  await paint(page); await evaluate();
  assert.ok(await page.locator('#evaluation-input .cm-line span').count() > 0, 'Real packaged CodeMirror highlights Ion');
  await page.locator('.tree-item[title="pricing:quotes#captured"]').click();
  await page.getByText('Unsupported input/output boundary: execution.boundary_function', { exact: true }).waitFor();
  assert.equal(await page.getByRole('button', { name: 'Evaluate', exact: true }).count(), 0);
  const nativeCalls = await page.evaluate(() => (window as unknown as ProbeWindow).platformProbe.native.map(raw => JSON.parse(raw).operation as string));
  assert.ok(nativeCalls.every(operation => operation === 'session.check'), `Worker workflows must not submit native execution or workspace operations: ${nativeCalls}`);
  if (mode === 'standalone') assert.deepEqual(nativeCalls, []);
  checks.push(`${mode}:compile-fields-json-ion-unsupported-boundary`);
}

let failure: string | null = null;
try {
  await until(async () => {
    if (exited) throw new Error(`Package exited before CDP startup: ${JSON.stringify(await exit)}`);
    return (await fetch(`http://127.0.0.1:${port}/json/version`).catch(() => null))?.ok === true;
  });
  const connection = { timeout: 30000, noDefaults: true };
  browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`, connection);
  const page = browser.contexts()[0]?.pages().find(page => new URL(page.url()).hostname === 'proton.localhost');
  assert.ok(page, 'The actual package serves its bundled main page'); page.setDefaultTimeout(20000);
  page.on('pageerror', error => errors.push(error.message));
  const resources: string[] = [];
  page.on('request', request => resources.push(request.url()));
  page.on('worker', worker => { workersStarted++; worker.once('close', () => { workersClosed++; }); });
  await page.reload(); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const original = page.url();
  profiles = (await readdir(profileRoot)).filter(name => name.startsWith('proton-cef-'));
  assert.equal(profiles.length, 1, 'This process creates one fresh CEF profile under its owned temporary root');
  const opened = value(await native<EmptyDescriptor>(page, 'session.open')); empty(opened);
  assert.deepEqual(value(await native(page, 'session.check', opened.sessionId)), opened);
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Desktop local');
  denied(await native(page, 'workspace.choose', opened.sessionId), 'unavailable');
  const submission = { contractVersion: '0.2.0-draft.1', model: '{}', entry: 'probe:main#answer', inputs: { format: 'json', source: '[]' } };
  denied(await native(page, 'execution.submit', opened.sessionId, submission), 'invalid_request');
  denied(await native(page, 'execution.submit', opened.sessionId, { ...submission, runtime: 'scheme', providerId: 'moonbit-scheme' }), 'unavailable');
  assert.deepEqual(value(await native(page, 'session.check', opened.sessionId)), opened, 'Unavailable effects preserve existing page authority');
  checks.push('empty-descriptor-and-unavailable-native-effects');
  await workerWorkflow(page, 'native-fallback');
  assert.ok(resources.every(url => { const value = new URL(url); return ['blob:', 'data:'].includes(value.protocol) || value.hostname === 'proton.localhost'; }), 'Bundled workflows must not depend on a development or external asset origin');
  await page.reload(); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  const replacement = value(await native<EmptyDescriptor>(page, 'session.open')); empty(replacement);
  assert.notEqual(replacement.sessionId, opened.sessionId);
  denied(await native(page, 'session.check', opened.sessionId), 'unauthorized');
  value(await native(page, 'session.close', replacement.sessionId));
  denied(await native(page, 'session.check', replacement.sessionId), 'unauthorized');
  checks.push('reload-and-close-revoke-old-session');
  const hostile = httpServer((_, response) => { response.writeHead(200, { 'Content-Type': 'text/html' }); response.end('<!doctype html><title>Untrusted origin</title>'); });
  try {
    hostile.listen(0, '127.0.0.1'); await once(hostile, 'listening');
    const bound = hostile.address(); assert.ok(bound && typeof bound !== 'string');
    await page.goto(`http://127.0.0.1:${bound.port}`);
    const access = await page.evaluate(async () => {
      if (typeof window.__MoonBit__?.core?.invokeOp !== 'function') return 'absent';
      return Promise.race([Promise.resolve(window.__MoonBit__.core.invokeOp('app:workbench_native', JSON.stringify({ profile: 'morphir/workbench/native', contractVersion: '0.2.0-draft.2', operation: 'session.open' }))).then(() => 'allowed', () => 'rejected'), new Promise(resolve => setTimeout(() => resolve('timeout'), 5000))]);
    });
    assert.ok(access === 'absent' || access === 'rejected', `Hostile origin must not obtain authority: ${access}`);
  } finally { hostile.closeAllConnections(); await new Promise<void>(resolve => hostile.close(() => resolve())); }
  checks.push('hostile-origin-denied');
  const standalone = new URL(original); standalone.search = '?mode=standalone';
  await page.goto(standalone.href); await page.getByRole('status').filter({ hasText: 'ready to compile' }).waitFor();
  assert.equal(await page.evaluate(() => globalThis.morphirWorkbench.runtimeLabel), 'Browser local');
  await workerWorkflow(page, 'standalone');
  await until(async () => workersStarted >= 8 && workersStarted === workersClosed && page.workers().length === 0, 10000);
  assert.deepEqual(errors, []); checks.push('actual-browser-workers-exit');
  await page.screenshot({ path: join(evidence, 'fallback.png'), fullPage: true });
  // This is the real CEF target/window close path. A forced supervisor cleanup
  // below cannot satisfy the normal entry-exit assertion.
  await page.close({ runBeforeUnload: true });
  await until(async () => exited, 15000);
  const result = await exit;
  assert.equal(result.kind, 'exit', JSON.stringify(result));
  assert.deepEqual({ code: result.result.code, signal: result.result.signal }, { code: 0, signal: null });
  await until(async () => !(await readdir(profileRoot)).some(name => name.startsWith('proton-cef-')), 10000);
  checks.push('real-window-close-and-profile-cleanup');
  await writeFile(join(evidence, 'package.log'), result.result.stdout + result.result.stderr);
  await writeFile(join(evidence, 'acceptance.json'), JSON.stringify({ profile: 'morphir/workbench/packaged-fallback', formatVersion: 1,
    target: target as Target, build, passed: true, checks, entry: basename(entry), files, workersStarted, workersClosed,
    profiles, profileRemoved: true, entryExit: { code: 0, signal: null }, forcedCleanup: false,
    helperCleanup: 'existing owned-process-group or Windows Job supervisor confirmed quiescence; remaining helpers may be reclaimed',
    scope: 'actual packaged CEF, empty native descriptor and browser-worker fallback; excludes native workers, OS pickers, Save dialogs and installers' }, null, 2) + '\n');
  console.log(`Actual ${target} packaged fallback passed: ${checks.length} checks, ${workersStarted} real workers closed.`);
} catch (error) {
  failure = String(error); throw error;
} finally {
  if (!exited) { forcedCleanup = true; await writeFile(cancelFile, 'cancel\n'); }
  const result = await exit;
  await browser?.close().catch(() => {});
  if (failure !== null) await writeFile(join(evidence, 'acceptance-failure.json'), JSON.stringify({ passed: false, target, build, failure, checks, result, forcedCleanup, quiescent, scratch }, null, 2) + '\n');
  if (quiescent) await rm(scratch, { recursive: true, force: true });
}
