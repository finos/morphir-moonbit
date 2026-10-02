import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LocalAdapter, RpcClient, ConnectedAdapter, chooseVersion, validateManifest } from './transport.js';

const source = { providerId: 'workspace', locator: 'workspace:demo', displayName: 'Demo' };
const manifest = {
  protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'test-session', initialSources: [source],
  providers: [{ id: 'workspace', status: 'available', capabilities: [
    'workspace/open', 'project-model/open', 'playground/catalog', 'playground/compile', 'playground/generate',
  ].map(name => ({ name: `morphir/${name}`, version: '1' })) }],
};
const catalog = {
  frontends: [{ languageId: 'scheme', displayName: 'Scheme', fileExtensions: ['.scm'], irVersions: ['3', '4.0.0'], compile: true }],
  targets: [{ target: 'scala', irVersions: ['4'], generate: true }],
};

class Socket extends EventTarget {
  readyState = 1;
  sent = [];
  send(message) { this.sent.push(JSON.parse(message)); }
  close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
  reply(data) { const event = new Event('message'); event.data = JSON.stringify(data); this.dispatchEvent(event); }
}

test('RPC correlates out-of-order replies and never reuses a request ID', async () => {
  const socket = new Socket();
  const rpc = new RpcClient(socket, 1000);
  const first = rpc.call('morphir.playground.catalog', {});
  const second = rpc.call('morphir.workspace.open', { source });
  assert.deepEqual(socket.sent[0], { jsonrpc: '2.0', id: 1, method: 'morphir.playground.catalog', params: {} });
  socket.reply({ jsonrpc: '2.0', method: 'morphir.workspace.event', params: { kind: 'snapshot' } });
  socket.reply({ jsonrpc: '2.0', id: 2, result: 'second' });
  socket.reply({ jsonrpc: '2.0', id: 1, result: 'first' });
  assert.equal(await first, 'first'); assert.equal(await second, 'second');
  const third = rpc.call('morphir.playground.catalog', {});
  assert.equal(socket.sent[2].id, 3);
  socket.reply({ jsonrpc: '2.0', id: 3, error: { code: -32013, message: 'Capability unavailable' } });
  await assert.rejects(third, /Capability unavailable/);
  rpc.dispose();
});

test('disconnect rejects pending RPC and later calls', async () => {
  const socket = new Socket(); const rpc = new RpcClient(socket);
  const pending = rpc.call('morphir.playground.catalog', {});
  socket.close();
  await assert.rejects(pending, /disconnected/);
  await assert.rejects(rpc.call('morphir.playground.catalog', {}), /not connected/);
});

test('invalid manifest and incompatible IR are refused before a request', () => {
  assert.throws(() => validateManifest({ ...manifest, protocolVersion: 2 }), /protocol v1/);
  assert.throws(() => validateManifest({ ...manifest, initialSources: [{ ...source, providerId: 'unknown' }] }), /unknown provider/);
  assert.equal(chooseVersion(catalog.frontends[0], catalog.targets[0]), '4.0.0');
  assert.equal(chooseVersion(catalog.frontends[0], { irVersions: ['3.0.0'] }), '3');
  assert.throws(() => chooseVersion(catalog.frontends[0], { irVersions: ['2'] }), /compatible IR/);
});

test('connected adapter emits upstream v1 initialize, source, compile and generate shapes', async () => {
  const calls = [];
  const ir = { formatVersion: 4, distribution: {} };
  const rpc = { async call(method, params) {
    calls.push({ method, params });
    if (method.endsWith('initialize')) return {};
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('workspace.open')) return { projects: [{ id: 'p1', name: 'Pricing' }] };
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) return { success: true, artifacts: [{ path: 'Main.scala', content: 'val answer = 42', binary: false }] };
    if (method.endsWith('project-model.open')) return { content: JSON.stringify(ir) };
    throw new Error(method);
  } };
  const inspected = [];
  const adapter = new ConnectedAdapter(rpc, manifest, { async execute(request) { inspected.push(request); return { success: true, ir, nodes: [] }; }, cancel() {} });
  const initialized = await adapter.initialize();
  assert.equal(initialized.connected, true);
  assert.deepEqual(calls[0], { method: 'morphir.session.initialize', params: { protocolVersion: 1, sessionId: 'test-session' } });
  assert.deepEqual(calls[2], { method: 'morphir.workspace.open', params: { source } });
  const result = await adapter.execute({ operation: 'compile', source: '(+ 20 22)', languageId: 'scheme', target: 'scala' });
  assert.deepEqual(calls[3], { method: 'morphir.playground.compile', params: {
    languageId: 'scheme', documents: [{ uri: 'file:///main.scm', languageId: 'scheme', version: 1, text: '(+ 20 22)' }],
    package: { name: 'user' }, irVersion: '4.0.0', options: {},
  } });
  assert.deepEqual(calls[4], { method: 'morphir.playground.generate', params: { ir, irVersion: '4.0.0', target: 'scala', options: {} } });
  assert.match(result.generated, /val answer = 42/);
  await adapter.execute({ operation: 'project', project: initialized.projects[0].id });
  assert.deepEqual(calls[5], { method: 'morphir.project-model.open', params: { source, projectId: 'p1' } });
  assert.deepEqual(inspected[0], { operation: 'inspect', source: JSON.stringify(ir) });
  await assert.rejects(adapter.execute({ operation: 'run' }), /does not offer evaluation/);
});

test('providers without compile capability leave compilation unavailable', async () => {
  const adapter = new ConnectedAdapter({ async call() { return catalog; } }, {
    ...manifest, initialSources: [], providers: [{ id: 'catalog-only', status: 'available', capabilities: [{ name: 'morphir/playground/catalog', version: '1' }] }],
  }, {});
  assert.equal((await adapter.initialize()).catalog.frontends.length, 0);
  await assert.rejects(adapter.execute({ operation: 'compile', languageId: 'scheme' }), /unavailable/);
});

test('worker cancellation terminates active execution and a new job gets a fresh worker', async () => {
  const workers = [];
  const adapter = new LocalAdapter(() => {
    const worker = { terminated: false, terminate() { this.terminated = true; }, postMessage(message) { this.message = message; } };
    workers.push(worker); return worker;
  });
  const first = adapter.execute({ operation: 'run', source: '(+ 1 2)' });
  adapter.cancel();
  await assert.rejects(first, /Cancelled/);
  assert.equal(workers[0].terminated, true);
  const second = adapter.execute({ operation: 'run', source: '(+ 20 22)' });
  workers[1].onmessage({ data: { id: workers[1].message.id, result: { success: true, value: '42' } } });
  assert.deepEqual(await second, { success: true, value: '42' });
  assert.equal(workers[1].terminated, true);
});

test('worker execution deadline ends the job', async () => {
  let terminated = false;
  const adapter = new LocalAdapter(() => ({ postMessage() {}, terminate() { terminated = true; } }), 5);
  await assert.rejects(adapter.execute({ operation: 'worksheet', source: '(+ 1 2)' }), /timed out/);
  assert.equal(terminated, true);
});

test('discarding a compile does not start inspection or generation after its reply', async () => {
  let resolveCompile;
  const calls = [];
  let inspections = 0;
  const adapter = new ConnectedAdapter({ async call(method) {
    calls.push(method);
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return new Promise(resolve => { resolveCompile = resolve; });
    return {};
  } }, { ...manifest, initialSources: [] }, { cancel() {}, async execute() { ++inspections; return { success: true }; } });
  await adapter.initialize();
  const compiling = adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 1 2)', target: 'scala' });
  adapter.cancel();
  resolveCompile({ success: true, ir: { formatVersion: 4 }, irVersion: '4.0.0', diagnostics: [] });
  await assert.rejects(compiling, /Discarded/);
  assert.equal(inspections, 0);
  assert.equal(calls.some(method => method.endsWith('generate')), false);
});

test('generator failure keeps successfully compiled IR available to inspect', async () => {
  const ir = { formatVersion: 4 };
  const adapter = new ConnectedAdapter({ async call(method) {
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) throw new Error('Generator disconnected');
    return {};
  } }, { ...manifest, initialSources: [] }, { async execute() { return { success: true, nodes: [] }; } });
  await adapter.initialize();
  const result = await adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 1 2)', target: 'scala' });
  assert.equal(result.success, true); assert.deepEqual(result.ir, ir);
  assert.equal(result.generationMessage, 'Generator disconnected');
});

test('oversized evaluation arguments are rejected before starting a worker', async () => {
  let workers = 0;
  const adapter = new LocalAdapter(() => { ++workers; throw new Error('Must not start'); });
  await assert.rejects(adapter.execute({ operation: 'evaluate', source: '{}', arguments: ['x'.repeat(16 * 1024 * 1024)] }), /arguments must be smaller/);
  assert.equal(workers, 0);
});

test('inspection rejection preserves host compilation and continues generation', async () => {
  const ir = { formatVersion: 4, padding: 'x'.repeat(16 * 1024 * 1024) };
  const calls = [];
  let workers = 0;
  const local = new LocalAdapter(() => { ++workers; throw new Error('Oversized inspection must not start'); });
  const adapter = new ConnectedAdapter({ async call(method, params) {
    calls.push({ method, params });
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) return { success: true, artifacts: [{ path: 'Main.scala', content: 'val answer = 42', binary: false }] };
    return {};
  } }, { ...manifest, initialSources: [] }, local);
  await adapter.initialize();
  const result = await adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 20 22)', target: 'scala' });
  assert.equal(result.success, true);
  assert.equal(result.ir, ir);
  assert.match(result.inspectionMessage, /16 MiB/);
  assert.match(result.generated, /val answer = 42/);
  assert.equal(workers, 0);
  assert.equal(calls.find(call => call.method.endsWith('generate')).params.ir, ir);
});

test('discard during rejected inspection never starts host generation', async () => {
  let started;
  let rejectInspection;
  let generated = false;
  const inspecting = new Promise(resolve => { started = resolve; });
  const local = {
    execute() { return new Promise((_, reject) => { rejectInspection = reject; started(); }); },
    cancel() { rejectInspection(new Error('Cancelled')); },
  };
  const adapter = new ConnectedAdapter({ async call(method) {
    if (method.endsWith('catalog')) return catalog;
    if (method.endsWith('compile')) return { success: true, ir: {}, irVersion: '4.0.0', diagnostics: [] };
    if (method.endsWith('generate')) { generated = true; return {}; }
    return {};
  } }, { ...manifest, initialSources: [] }, local);
  await adapter.initialize();
  const compiling = adapter.execute({ operation: 'compile', languageId: 'scheme', source: '(+ 20 22)', target: 'scala' });
  await inspecting;
  adapter.cancel();
  await assert.rejects(compiling, /Discarded/);
  assert.equal(generated, false);
});


test('oversized Ion input is rejected before starting a worker', async () => {
  let workers = 0;
  const adapter = new LocalAdapter(() => { ++workers; throw new Error('Must not start'); });
  await assert.rejects(adapter.execute({ operation: 'evaluate', source: '{}', argumentsIon: 'x'.repeat(16 * 1024 * 1024 + 1) }), /Ion arguments must be smaller/);
  assert.equal(workers, 0);
});
