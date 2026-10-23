import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ModelOriginalsConnectionLimits, openModelOriginalsSession,
  type ModelOriginalsObservation, type ModelOriginalsLifecycleProducer, type ModelOriginalsManifestPort,
  type ModelOriginalsExchangePort, type ModelOriginalsExchangeStart,
} from './model-originals-session.ts';

const profile = 'morphir/workbench/model-originals';
const version = '0.1.0-draft.1';
const root = { providerId: 'provider-A', locator: 'workspace:orders', displayName: 'Orders' };
const project = { id: '["provider-A","workspace:orders","packages/orders"]', name: 'Pricing', state: 'unloaded' };
const manifest = () => ({ protocolVersion: 1, webSocketPath: '/rpc', sessionId: 'session-A',
  providers: [{ id: 'provider-A', name: 'Morphir connected', kind: 'connected', status: 'available', capabilities: [
    { name: 'morphir/workspace/open', version: '1' }, { name: profile, version },
  ] }], initialSources: [root] });
const snapshot = () => ({ snapshot: { id: 'workspace-A', root, name: 'Orders', configAnchor: null,
  state: 'open', projects: [project], modelSources: [], knowledgeBaseSources: [], diagnostics: [] } });
const unavailable = { profile, contractVersion: version, status: 'unavailable', reason: 'not_compiled' };
const limits = () => ModelOriginalsConnectionLimits.create({ manifestBytes: 128 * 1024 });
type Request = { id: number; method: string; params: Record<string, unknown> };

class Socket extends EventTarget {
  readyState = 1;
  closes = 0;
  requests: string[] = [];
  readonly respond: (request: Request) => string | undefined;
  readonly beforeSend: ((raw: string) => void) | undefined;
  constructor(respond: (request: Request) => string | undefined, beforeSend?: (raw: string) => void) {
    super(); this.respond = respond; this.beforeSend = beforeSend;
  }
  send(raw: string) {
    this.beforeSend?.(raw);
    this.requests.push(raw);
    queueMicrotask(() => {
      const reply = this.respond(JSON.parse(raw) as Request);
      if (reply !== undefined) this.dispatchEvent(new MessageEvent('message', { data: reply }));
    });
  }
  close() { ++this.closes; this.readyState = 3; this.dispatchEvent(new Event('close')); }
}
function peer(request: Request) {
  const result = request.method === 'morphir.session.initialize' ? { protocolVersion: 1 }
    : request.method === 'morphir.workspace.open' ? snapshot() : unavailable;
  return JSON.stringify({ jsonrpc: '2.0', id: request.id, result });
}
function fixture(options: { manifestRaw?: string; respond?: (request: Request) => string | undefined; status?: number;
  onObservation?: (event: ModelOriginalsObservation) => void; lifecycle?: ModelOriginalsLifecycleProducer;
  beforeFetch?: () => void; beforeSend?: (raw: string) => void } = {}) {
  let fetched = 0, sockets = 0;
  const socket = new Socket(options.respond ?? peer, options.beforeSend);
  const abort = new AbortController();
  const observations: ModelOriginalsObservation[] = [];
  const open = () => openModelOriginalsSession(new URL('http://morphir.local/workbench'), {
    limits: limits(), signal: abort.signal,
    fetch: async (input, init) => {
      options.beforeFetch?.();
      ++fetched;
      assert.equal(String(input), 'http://morphir.local/api/session');
      assert.equal(init?.credentials, 'same-origin'); assert.equal(init?.cache, 'no-store');
      assert.equal(init?.signal, abort.signal);
      return new Response(options.manifestRaw ?? JSON.stringify(manifest()), { status: options.status ?? 200 });
    },
    createSocket: url => { ++sockets; assert.equal(url, 'ws://morphir.local/rpc'); return socket; },
    observe: event => { observations.push(event); options.onObservation?.(event); },
    lifecycle: options.lifecycle,
  });
  return { open, socket, abort, observations, counts: () => ({ fetched, sockets }) };
}

test('lifecycle begins before actual ports and resolves only decoded business operations', async () => {
  const order: string[] = [];
  const lifecycle: ModelOriginalsLifecycleProducer = {
    beginManifest(request) {
      assert(Object.isFrozen(request)); assert.equal(request.url, 'http://morphir.local/api/session');
      order.push('manifest-pending');
      return {resolved(value) {assert(Object.isFrozen(value)); assert.equal(value.outcome, 'offered');
        assert.equal(value.raw, JSON.stringify(manifest())); order.push('manifest-resolved');},
      rejected() {assert.fail('The actual manifest must succeed.');}};
    },
    beginExchange(request) {
      assert(Object.isFrozen(request));
      const literal = JSON.parse(request.request) as Request;
      assert.equal(String(literal.id), request.requestId); assert.equal(literal.method, request.method);
      order.push(`pending:${request.requestId}`);
      return {resolved(value) {assert(Object.isFrozen(value)); assert.equal(value.reply, peer(literal));
        order.push(`resolved:${request.requestId}`);}, rejected() {assert.fail('The actual decoded exchange must succeed.');}};
    },
    poisoned() {assert.fail('Healthy lifecycle observation must not poison.');},
  };
  const f = fixture({lifecycle, beforeFetch() {assert.equal(order.at(-1), 'manifest-pending');},
    beforeSend(raw) {assert.equal(order.at(-1), `pending:${(JSON.parse(raw) as Request).id}`);}});
  const opened = await f.open(); assert(opened.kind === 'ready');
  try {
    await opened.session.openSource(opened.session.sources[0]!);
    assert.deepEqual(order, ['manifest-pending', 'manifest-resolved', 'pending:1', 'resolved:1', 'pending:2', 'resolved:2']);
  } finally {opened.session.close();}
});

type Terminal<R, E> = {kind: 'pending'} | {kind: 'resolved'; value: R} | {kind: 'rejected'; value: E};
/** Trusted port fixtures assert the seam only, not a product registry/report. */
function lifecycleTrace() {
  const manifests: Array<{request: Readonly<{url: string}>; terminal: Terminal<Parameters<ModelOriginalsManifestPort['resolved']>[0], Parameters<ModelOriginalsManifestPort['rejected']>[0]>}> = [];
  const exchanges: Array<{request: ModelOriginalsExchangeStart; terminal: Terminal<Parameters<ModelOriginalsExchangePort['resolved']>[0], Parameters<ModelOriginalsExchangePort['rejected']>[0]>}> = [];
  const poisoned: unknown[] = [];
  const producer: ModelOriginalsLifecycleProducer = {
    beginManifest(request) {
      const record: typeof manifests[number] = {request, terminal: {kind: 'pending'}}; manifests.push(record);
      return {resolved(value) {assert.equal(record.terminal.kind, 'pending'); record.terminal = {kind: 'resolved', value};},
        rejected(value) {assert.equal(record.terminal.kind, 'pending'); record.terminal = {kind: 'rejected', value};}};
    },
    beginExchange(request) {
      const record: typeof exchanges[number] = {request, terminal: {kind: 'pending'}}; exchanges.push(record);
      return {resolved(value) {assert.equal(record.terminal.kind, 'pending'); record.terminal = {kind: 'resolved', value};},
        rejected(value) {assert.equal(record.terminal.kind, 'pending'); record.terminal = {kind: 'rejected', value};}};
    },
    poisoned(cause) {poisoned.push(cause);},
  };
  return {producer, manifests, exchanges, poisoned};
}

test('manifest lifecycle includes bounded body and offer validation before socket setup', async () => {
  const trace = lifecycleTrace(), socket = new Socket(peer), abort = new AbortController();
  let body!: ReadableStreamDefaultController<Uint8Array>, started!: () => void, sockets = 0;
  const reading = new Promise<void>(resolve => {started = resolve;});
  const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: abort.signal, lifecycle: trace.producer,
    fetch: async () => {
      assert.equal(trace.manifests[0]!.terminal.kind, 'pending');
      return new Response(new ReadableStream({start(controller) {body = controller;}, pull() {started();}}));
    }, createSocket: () => {sockets++; assert.equal(trace.manifests[0]!.terminal.kind, 'resolved'); return socket;},
  });
  await reading; assert.equal(trace.manifests[0]!.terminal.kind, 'pending'); assert.equal(sockets, 0);
  body.enqueue(new TextEncoder().encode(JSON.stringify(manifest()))); body.close();
  const opened = await pending; assert(opened.kind === 'ready'); opened.session.close();
  assert.equal(trace.manifests.length, 1); assert.equal(trace.exchanges.length, 1); assert.deepEqual(trace.poisoned, []);
});

test('manifest lifecycle rejects actual fetch, body and offer failures without claiming success', async () => {
  const actualFetchError = new Error('actual fetch refusal');
  for (const stage of ['fetch', 'body', 'offer'] as const) {
    const trace = lifecycleTrace(); let sockets = 0;
    const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
      limits: limits(), signal: new AbortController().signal, lifecycle: trace.producer,
      fetch: async () => {
        if (stage === 'fetch') throw actualFetchError;
        return new Response(stage === 'body' ? new Uint8Array([0xff]) : '{malformed');
      }, createSocket: () => {sockets++; return new Socket(peer);},
    });
    await assert.rejects(pending, cause => {
      const terminal = trace.manifests[0]!.terminal; assert(terminal.kind === 'rejected');
      assert.strictEqual(terminal.value.cause, cause);
      assert.deepEqual(terminal.value.response, stage === 'fetch' ? {kind: 'not-received'} : {
        kind: 'received', body: stage === 'body' ? {kind: 'not-complete'} : {kind: 'complete', raw: '{malformed'},
      });
      if (stage === 'fetch') assert.strictEqual(cause, actualFetchError);
      return true;
    });
    assert.equal(trace.manifests.length, 1); assert.equal(trace.exchanges.length, 0); assert.equal(sockets, 0);
  }
  const offered = manifest(); offered.providers[0]!.capabilities.pop();
  const trace = lifecycleTrace(), f = fixture({lifecycle: trace.producer, manifestRaw: JSON.stringify(offered)});
  assert.deepEqual(await f.open(), {kind: 'unavailable', reason: 'not-offered'});
  const terminal = trace.manifests[0]!.terminal; assert(terminal.kind === 'resolved');
  assert.equal(terminal.value.outcome, 'not-offered'); assert.equal(trace.exchanges.length, 0); assert.equal(f.counts().sockets, 0);
});

test('decoded exchange rejection retains a fulfilled raw transport reply and the exact business error', async () => {
  const raw = '{"jsonrpc":"2.0","id":1.0,"result":{"protocolVersion":1}}';
  const trace = lifecycleTrace(), f = fixture({lifecycle: trace.producer, respond: () => raw});
  await assert.rejects(f.open(), cause => {
    const terminal = trace.exchanges[0]!.terminal; assert(terminal.kind === 'rejected');
    assert.strictEqual(terminal.value.cause, cause); assert.deepEqual(terminal.value.response, {kind: 'returned', reply: raw});
    assert.equal(f.socket.closes, 1); return true;
  });
  assert.equal(trace.exchanges.length, 1); assert.deepEqual(trace.poisoned, []);
});

test('pending lifecycle exchange survives overlap refusal and retains one actual cancellation terminal', async () => {
  const trace = lifecycleTrace(), f = fixture({lifecycle: trace.producer,
    respond: request => request.method === 'morphir.workspace.open' ? undefined : peer(request)});
  const opened = await f.open(); assert(opened.kind === 'ready');
  const pending = opened.session.openSource(opened.session.sources[0]!);
  assert.equal(trace.exchanges[1]!.terminal.kind, 'pending');
  await assert.rejects(opened.session.openSource(opened.session.sources[0]!), /pending/);
  assert.equal(trace.exchanges.length, 2); f.abort.abort();
  await assert.rejects(pending, cause => {
    const terminal = trace.exchanges[1]!.terminal; assert(terminal.kind === 'rejected');
    assert.strictEqual(terminal.value.cause, cause); assert.deepEqual(terminal.value.response, {kind: 'not-returned'}); return true;
  });
  f.socket.dispatchEvent(new MessageEvent('message', {data: peer(JSON.parse(f.socket.requests[1]!) as Request)}));
  opened.session.close(); assert.equal(trace.exchanges.length, 2); assert.equal(f.socket.closes, 1);
});

test('lifecycle observation failures poison once without changing ordinary successful work', async () => {
  for (const stage of ['manifest-begin', 'manifest-resolved', 'exchange-begin', 'exchange-resolved'] as const) {
    const observationError = new Error(`actual ${stage} observation failure`), trace = lifecycleTrace();
    const producer: ModelOriginalsLifecycleProducer = {
      beginManifest(request) {
        if (stage === 'manifest-begin') throw observationError;
        const port = trace.producer.beginManifest(request);
        return {...port, resolved(value) {port.resolved(value); if (stage === 'manifest-resolved') throw observationError;}};
      },
      beginExchange(request) {
        if (stage === 'exchange-begin') throw observationError;
        const port = trace.producer.beginExchange(request);
        return {...port, resolved(value) {port.resolved(value); if (stage === 'exchange-resolved') throw observationError;}};
      },
      poisoned(cause) {trace.poisoned.push(cause); throw new Error('a secondary poison callback must not raise');},
    };
    const f = fixture({lifecycle: producer}), opened = await f.open(); assert(opened.kind === 'ready');
    const projects = await opened.session.openSource(opened.session.sources[0]!);
    const exchange = await opened.session.exchangeCapture(projects[0]!, {scope: 'complete', semantic: 'none'});
    assert.equal(exchange.requestId, '3'); assert.deepEqual(trace.poisoned, [observationError]);
    assert.equal(trace.exchanges.length, stage === 'exchange-resolved' ? 1 : 0, 'poisoned producer is never called again');
    opened.session.close(); assert.equal(f.socket.closes, 1);
  }
});

test('send failure and rejected-observer failure retain the identical business cause and cleanup', async () => {
  const businessError = new Error('actual socket send failed'), observationError = new Error('actual rejection observer failed');
  const trace = lifecycleTrace();
  const producer: ModelOriginalsLifecycleProducer = {...trace.producer,
    beginExchange(request) {
      const port = trace.producer.beginExchange(request);
      return {...port, rejected(value) {port.rejected(value); throw observationError;}};
    }};
  const f = fixture({lifecycle: producer, beforeSend() {throw businessError;}});
  await assert.rejects(f.open(), cause => cause === businessError);
  const terminal = trace.exchanges[0]!.terminal; assert(terminal.kind === 'rejected');
  assert.strictEqual(terminal.value.cause, businessError); assert.deepEqual(terminal.value.response, {kind: 'not-returned'});
  assert.deepEqual(trace.poisoned, [observationError]); assert.equal(f.socket.closes, 1);
});

test('new lifecycle observation preserves legacy observer rejection semantics and raw response', async () => {
  const legacyError = new Error('actual legacy observer failure'), trace = lifecycleTrace();
  const f = fixture({lifecycle: trace.producer, onObservation(event) {if (event.kind === 'exchange') throw legacyError;}});
  await assert.rejects(f.open(), cause => cause === legacyError);
  const terminal = trace.exchanges[0]!.terminal; assert(terminal.kind === 'rejected');
  assert.strictEqual(terminal.value.cause, legacyError); assert.equal(terminal.value.response.kind, 'returned');
  assert.deepEqual(trace.poisoned, []); assert.equal(f.socket.closes, 1);
});

test('reentrant lifecycle begin cannot fetch or send after actual abort or close', async () => {
  const abortedTrace = lifecycleTrace();
  const aborted = fixture({lifecycle: {...abortedTrace.producer, beginManifest(request) {
    const port = abortedTrace.producer.beginManifest(request); aborted.abort.abort(); return port;
  }}});
  await assert.rejects(aborted.open(), /cancel/);
  assert.deepEqual(aborted.counts(), {fetched: 0, sockets: 0});
  const manifestTerminal = abortedTrace.manifests[0]!.terminal; assert(manifestTerminal.kind === 'rejected');
  assert.deepEqual(manifestTerminal.value.response, {kind: 'not-received'});
  const trace = lifecycleTrace();
  let session: Awaited<ReturnType<typeof openModelOriginalsSession>>;
  const f = fixture({lifecycle: {...trace.producer, beginExchange(request) {
    const port = trace.producer.beginExchange(request);
    if (request.method === 'morphir.workspace.open' && session.kind === 'ready') session.session.close();
    return port;
  }}});
  session = await f.open(); assert(session.kind === 'ready');
  await assert.rejects(session.session.openSource(session.session.sources[0]!), /closed/);
  assert.equal(f.socket.requests.length, 1); assert.equal(f.socket.closes, 1);
  const terminal = trace.exchanges[1]!.terminal; assert(terminal.kind === 'rejected');
  assert.deepEqual(terminal.value.response, {kind: 'not-returned'});
});

test('manifest helper success stays distinct from cancellation at the new outer await boundary', async () => {
  const trace = lifecycleTrace(), abort = new AbortController(); let sockets = 0;
  const producer: ModelOriginalsLifecycleProducer = {...trace.producer, beginManifest(request) {
    const port = trace.producer.beginManifest(request);
    return {...port, resolved(value) {port.resolved(value); queueMicrotask(() => abort.abort());}};
  }};
  await assert.rejects(openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: abort.signal, lifecycle: producer,
    fetch: async () => new Response(JSON.stringify(manifest())), createSocket: () => {sockets++; return new Socket(peer);},
  }), /cancel/);
  assert.equal(trace.manifests[0]!.terminal.kind, 'resolved'); assert.equal(trace.manifests.length, 1);
  assert.equal(trace.exchanges.length, 0); assert.equal(sockets, 0);
});

test('legacy manifest microtask cancellation refuses before socket with lifecycle absent or present', async () => {
  for (const observed of [false, true]) {
    const trace = lifecycleTrace(), abort = new AbortController(); let sockets = 0;
    await assert.rejects(openModelOriginalsSession(new URL('http://morphir.local'), {
      limits: limits(), signal: abort.signal, lifecycle: observed ? trace.producer : undefined,
      fetch: async () => new Response(JSON.stringify(manifest())),
      observe(event) {if (event.kind === 'manifest') queueMicrotask(() => abort.abort());},
      createSocket: () => {sockets++; return new Socket(peer);},
    }), cause => cause instanceof Error && cause.message === 'Model originals connection: Opening cancelled.');
    assert.equal(sockets, 0); assert.equal(trace.exchanges.length, 0);
    assert.equal(trace.manifests.length, observed ? 1 : 0);
    if (observed) assert.equal(trace.manifests[0]!.terminal.kind, 'resolved');
  }
});

test('guard refusals before the first actual port do not read or begin lifecycle observation', async () => {
  const trace = lifecycleTrace(), abort = new AbortController(); abort.abort();
  let reads = 0;
  for (const base of [new URL('http://morphir.local'), new URL('file:///no-network')]) {
    await assert.rejects(openModelOriginalsSession(base, {
      limits: limits(), signal: base.protocol === 'file:' ? new AbortController().signal : abort.signal,
      get lifecycle() {reads++; return trace.producer;}, fetch: async () => {throw new Error('No fetch allowed.');},
    }));
  }
  assert.equal(reads, 0); assert.deepEqual(trace.manifests, []); assert.deepEqual(trace.exchanges, []);
});

test('an aborting lifecycle accessor prevents fetch even when absent or throwing', async () => {
  for (const throwing of [false, true]) {
    const abort = new AbortController(); let fetched = 0, sockets = 0, reads = 0;
    await assert.rejects(openModelOriginalsSession(new URL('http://morphir.local'), {
      limits: limits(), signal: abort.signal,
      get lifecycle(): ModelOriginalsLifecycleProducer | undefined {
        reads++; abort.abort();
        if (throwing) throw new Error('actual lifecycle getter failed after cancellation');
        return undefined;
      },
      fetch: async () => {fetched++; return new Response(JSON.stringify(manifest()));},
      createSocket: () => {sockets++; return new Socket(peer);},
    }), cause => cause instanceof Error && cause.message === 'Model originals connection: Opening cancelled.');
    assert.equal(reads, 1); assert.equal(fetched, 0); assert.equal(sockets, 0);
  }
});

test('malformed and accessor-failing observers poison without changing the business result', async () => {
  for (const shape of ['missing', 'getter'] as const) {
    const actualError = new Error('actual observer accessor failed'), poisoned: unknown[] = [];
    const producer: ModelOriginalsLifecycleProducer = {
      beginManifest() {return shape === 'missing' ? undefined as never : {
        get resolved(): ModelOriginalsManifestPort['resolved'] {throw actualError;}, rejected() {},
      };},
      beginExchange() {throw new Error('Poisoned observation must not be reused.');}, poisoned(cause) {poisoned.push(cause);},
    };
    const f = fixture({lifecycle: producer}), opened = await f.open(); assert(opened.kind === 'ready');
    opened.session.close(); assert.equal(poisoned.length, 1);
    if (shape === 'getter') assert.strictEqual(poisoned[0], actualError);
    assert.equal(f.socket.closes, 1);
  }
});

test('a rejected asynchronous terminal observer cannot become an unhandled business failure', async () => {
  const actualError = new Error('actual asynchronous observation failure'), trace = lifecycleTrace();
  const producer: ModelOriginalsLifecycleProducer = {...trace.producer, beginExchange(request) {
    const port = trace.producer.beginExchange(request);
    return {...port, async resolved(value) {port.resolved(value); await Promise.resolve(); throw actualError;}};
  }};
  const f = fixture({lifecycle: producer}), opened = await f.open(); assert(opened.kind === 'ready');
  await Promise.resolve(); await Promise.resolve();
  assert.equal(trace.poisoned.length, 1); assert(trace.poisoned[0] instanceof TypeError);
  const projects = await opened.session.openSource(opened.session.sources[0]!);
  assert.equal(projects.length, 1); assert.equal(trace.exchanges.length, 1);
  opened.session.close(); assert.equal(f.socket.closes, 1);
});

test('a fulfilled asynchronous terminal observer poisons synchronously before another actual port', async () => {
  const trace = lifecycleTrace();
  const producer: ModelOriginalsLifecycleProducer = {...trace.producer, beginManifest(request) {
    const port = trace.producer.beginManifest(request);
    return {...port, async resolved(value) {port.resolved(value); await Promise.resolve();}};
  }};
  const f = fixture({lifecycle: producer, beforeSend() {
    assert.equal(trace.poisoned.length, 1, 'async terminal return must poison before business continuation');
    assert(trace.poisoned[0] instanceof TypeError);
  }});
  const opened = await f.open(); assert(opened.kind === 'ready');
  assert.equal(trace.manifests[0]!.terminal.kind, 'resolved');
  assert.equal(trace.exchanges.length, 0, 'poisoned observation cannot create another port');
  opened.session.close(); assert.equal(f.socket.closes, 1);
});

test('an invalid asynchronous begin poisons observation without leaking its rejected Promise', async () => {
  const trace = lifecycleTrace(), actualError = new Error('actual invalid asynchronous begin');
  const producer: ModelOriginalsLifecycleProducer = {...trace.producer,
    beginManifest: (async () => {throw actualError;}) as unknown as ModelOriginalsLifecycleProducer['beginManifest'],
  };
  const f = fixture({lifecycle: producer}), opened = await f.open(); assert(opened.kind === 'ready');
  await Promise.resolve(); assert.equal(trace.poisoned.length, 1); assert(trace.poisoned[0] instanceof TypeError);
  opened.session.close(); assert.equal(f.socket.closes, 1);
});

test('actual initialization, discovery and capture share one monotonic request sequence', async () => {
  const f = fixture(); const opened = await f.open(); assert.equal(opened.kind, 'ready');
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session;
  assert.equal(session.sources.length, 1);
  const projects = await session.openSource(session.sources[0]!);
  assert.equal(projects.length, 1); assert.equal(projects[0]!.name, 'Pricing');
  const exchange = await session.exchangeCapture(projects[0]!, { scope: 'complete', semantic: 'projection' });
  assert.equal(exchange.requestId, '3');
  assert.deepEqual(f.socket.requests.map(raw => JSON.parse(raw) as Request), [
    { jsonrpc: '2.0', id: 1, method: 'morphir.session.initialize', params: { protocolVersion: 1, sessionId: 'session-A' } },
    { jsonrpc: '2.0', id: 2, method: 'morphir.workspace.open', params: { source: root } },
    { jsonrpc: '2.0', id: 3, method: 'morphir.model-originals.capture', params: {
      contractVersion: version, source: { providerId: 'provider-A', locator: 'workspace:orders' },
      projectId: project.id, scope: 'complete', semantic: 'projection',
    } },
  ]);
  assert.equal(exchange.reply, JSON.stringify({ jsonrpc: '2.0', id: 3, result: unavailable }));
  assert(Object.isFrozen(projects[0]));
  assert.equal(f.observations.filter(event => event.kind === 'exchange').length, 3);
  await assert.rejects(session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' }), /capture|closed/i);
  assert.equal(f.socket.requests.length, 3);
  session.close(); session.close(); assert.equal(f.socket.closes, 1);
});

test('absent, incompatible or disconnected offers never create a socket or downgrade', async () => {
  for (const change of ['absent', 'version', 'disconnected']) {
    const offered = manifest();
    if (change === 'absent') offered.providers[0]!.capabilities.pop();
    if (change === 'version') offered.providers[0]!.capabilities[1]!.version = '0.1.0-draft.2';
    if (change === 'disconnected') offered.providers[0]!.status = 'disconnected';
    const f = fixture({ manifestRaw: JSON.stringify(offered) });
    assert.deepEqual(await f.open(), { kind: 'unavailable', reason: 'not-offered' });
    assert.deepEqual(f.counts(), { fetched: 1, sockets: 0 });
  }
});

test('authentication, duplicate manifest members and ambiguous offers refuse before socket effects', async () => {
  const duplicate = JSON.stringify(manifest()).replace('"sessionId":"session-A"', '"sessionId":"session-A","sessionId":"session-A"');
  const ambiguous = manifest(); ambiguous.providers[0]!.capabilities.push({ name: profile, version });
  for (const options of [{ status: 401 }, { status: 403 }, { manifestRaw: duplicate }, { manifestRaw: JSON.stringify(ambiguous) }]) {
    const f = fixture(options); await assert.rejects(f.open());
    assert.equal(f.counts().sockets, 0);
  }
});

test('literal initialize correlation and protocol checks precede workspace discovery', async () => {
  for (const raw of [
    '{"jsonrpc":"2.0","id":2,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1.0,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1,"id":1,"result":{"protocolVersion":1}}',
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":2}}',
    '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1},"error":{"code":-32000,"message":"bad"}}',
  ]) {
    const f = fixture({ respond: () => raw }); await assert.rejects(f.open());
    assert.equal(f.socket.requests.length, 1); assert.equal(f.socket.closes, 1);
  }
});

test('project selections belong to their actual connection and preserve IDs despite equal labels', async () => {
  const f = fixture({ respond: request => request.method === 'morphir.workspace.open'
    ? JSON.stringify({ jsonrpc: '2.0', id: request.id, result: { snapshot: { ...snapshot().snapshot,
      projects: [project, { ...project, id: 'another-project' }] } } }) : peer(request) });
  const a = await f.open(); const g = fixture(); const b = await g.open();
  assert.equal(a.kind, 'ready'); assert.equal(b.kind, 'ready');
  if (a.kind !== 'ready' || b.kind !== 'ready') throw new Error('Missing session');
  const projects = await a.session.openSource(a.session.sources[0]!);
  assert.deepEqual(projects.map(p => p.projectId), [project.id, 'another-project']);
  await assert.rejects(b.session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' }), /selection/i);
  assert.equal(g.socket.requests.length, 1);
  a.session.close(); assert.equal(f.socket.closes, 1); assert.equal(g.socket.closes, 0);
  b.session.close();
});

test('foreign snapshot roots and duplicate actual project IDs never create usable selections', async () => {
  for (const bad of [
    { ...snapshot().snapshot, root: { ...root, providerId: 'foreign' } },
    { ...snapshot().snapshot, projects: [project, project] },
  ]) {
    const f = fixture({ respond: request => request.method === 'morphir.workspace.open'
      ? JSON.stringify({ jsonrpc: '2.0', id: request.id, result: { snapshot: bad } }) : peer(request) });
    const result = await f.open(); if (result.kind !== 'ready') throw new Error('Missing session');
    await assert.rejects(result.session.openSource(result.session.sources[0]!));
    assert.equal(f.socket.requests.length, 2); assert.equal(f.socket.closes, 1);
  }
});

test('an aborted opener performs no effects, and abort after initialization closes only its owned channel', async () => {
  const before = fixture(); before.abort.abort(); await assert.rejects(before.open(), /cancel/i);
  assert.deepEqual(before.counts(), { fetched: 0, sockets: 0 });
  const active = fixture(); const other = fixture();
  const a = await active.open(); const b = await other.open();
  if (a.kind !== 'ready' || b.kind !== 'ready') throw new Error('Missing session');
  active.abort.abort(); assert.equal(active.socket.closes, 1); assert.equal(other.socket.closes, 0);
  await assert.rejects(a.session.openSource(a.session.sources[0]!), /closed|cancel/i);
  b.session.close();
});

test('the production factory uses actual HTTP and WebSocket initialization without replacing its state', async () => {
  const requests: string[] = [];
  const trace = lifecycleTrace();
  const server = Bun.serve({ port: 0,
    fetch(request, server) {
      if (new URL(request.url).pathname === '/api/session') {
        assert.equal(trace.manifests[0]!.terminal.kind, 'pending'); return Response.json(manifest());
      }
      if (server.upgrade(request)) return;
      return new Response('Not found', { status: 404 });
    }, websocket: { message(socket, raw) {
      assert.equal(typeof raw, 'string'); requests.push(String(raw));
      assert.equal(trace.exchanges.at(-1)!.terminal.kind, 'pending');
      socket.send(peer(JSON.parse(String(raw)) as Request));
    } },
  });
  try {
    const opened = await openModelOriginalsSession(new URL(server.url), { limits: limits(), signal: new AbortController().signal, lifecycle: trace.producer });
    if (opened.kind !== 'ready') throw new Error('Missing actual initialized session');
    const projects = await opened.session.openSource(opened.session.sources[0]!);
    const result = await opened.session.exchangeCapture(projects[0]!, { scope: 'primary', semantic: 'none' });
    assert.equal(result.requestId, '3');
    assert.deepEqual(requests.map(raw => (JSON.parse(raw) as Request).id), [1, 2, 3]);
    assert.equal(trace.manifests[0]!.terminal.kind, 'resolved');
    assert.deepEqual(trace.exchanges.map(port => port.terminal.kind), ['resolved', 'resolved', 'resolved']);
    opened.session.close();
  } finally { await server.stop(true); }
});

test('manifest budgets use streamed UTF-8 bytes, including split multibyte input and exact limits', async () => {
  const value = manifest(); value.initialSources[0]!.displayName = 'Orders 🐟';
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  for (const maximum of [bytes.length, bytes.length - 1]) {
    let sockets = 0;
    const socket = new Socket(peer);
    const start = bytes.indexOf(0xf0) + 1;
    const result = openModelOriginalsSession(new URL('http://morphir.local'), {
      limits: ModelOriginalsConnectionLimits.create({ manifestBytes: maximum }), signal: new AbortController().signal,
      fetch: async () => new Response(new ReadableStream({ start(controller) {
        controller.enqueue(bytes.slice(0, start)); controller.enqueue(bytes.slice(start)); controller.close();
      } })), createSocket: () => { ++sockets; return socket; },
    });
    if (maximum === bytes.length) {
      const opened = await result; assert.equal(opened.kind, 'ready');
      if (opened.kind === 'ready') opened.session.close();
      assert.equal(sockets, 1);
    } else { await assert.rejects(result, /byte limit/i); assert.equal(sockets, 0); }
  }
  for (const maximum of [0, -1, 1.1, Infinity, 131073])
    assert.throws(() => ModelOriginalsConnectionLimits.create({ manifestBytes: maximum }));
  let sockets = 0;
  await assert.rejects(openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: new AbortController().signal,
    fetch: async () => new Response(new Uint8Array([0xff])), createSocket: () => { ++sockets; return new Socket(peer); },
  }));
  assert.equal(sockets, 0);
});

test('discovery cannot redirect a socket to another origin or embed credentials and fragments', async () => {
  for (const webSocketPath of ['//elsewhere.test/rpc', 'https://elsewhere.test/rpc',
    'http://user:mypassword@morphir.local/rpc', '/rpc#fragment']) {
    const offered = { ...manifest(), webSocketPath };
    const f = fixture({ manifestRaw: JSON.stringify(offered) }); await assert.rejects(f.open());
    assert.equal(f.counts().sockets, 0);
  }
});

test('refreshing discovery invalidates earlier project selections without resetting request IDs', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session, source = session.sources[0]!;
  const first = await session.openSource(source), current = await session.openSource(source);
  await assert.rejects(session.exchangeCapture(first[0]!, { scope: 'primary', semantic: 'none' }), /stale/i);
  assert.equal(f.socket.requests.length, 3);
  const exchanged = await session.exchangeCapture(current[0]!, { scope: 'primary', semantic: 'none' });
  assert.equal(exchanged.requestId, '4'); session.close();
});

test('copied discovery objects and invalid capture options cannot grant request authority', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const session = opened.session;
  await assert.rejects(session.openSource({ ...session.sources[0]! }), /selection/i);
  const projects = await session.openSource(session.sources[0]!);
  await assert.rejects(session.exchangeCapture({ ...projects[0]! }, { scope: 'primary', semantic: 'none' }), /selection/i);
  await assert.rejects(session.exchangeCapture(projects[0]!, { scope: 'everything' as never, semantic: 'none' }));
  assert.equal(f.socket.requests.length, 2); session.close();
});

test('pending requests reject overlapping discovery and settle on actual cancellation', async () => {
  const f = fixture({ respond: request => request.method === 'morphir.workspace.open' ? undefined : peer(request) });
  const opened = await f.open(); if (opened.kind !== 'ready') throw new Error('Missing session');
  const pending = opened.session.openSource(opened.session.sources[0]!);
  await assert.rejects(opened.session.openSource(opened.session.sources[0]!), /pending/i);
  assert.equal(f.socket.requests.length, 2); f.abort.abort();
  await assert.rejects(pending, /closed|cancel/i); assert.equal(f.socket.closes, 1);
});

test('observer reentrancy cannot publish discovery after its connection is cancelled', async () => {
  const f = fixture({ onObservation: event => {
    if (event.kind === 'exchange' && event.method === 'morphir.workspace.open') f.abort.abort();
  } });
  const opened = await f.open(); if (opened.kind !== 'ready') throw new Error('Missing session');
  await assert.rejects(opened.session.openSource(opened.session.sources[0]!), /closed|cancel/i);
  assert.equal(f.socket.requests.length, 2); assert.equal(f.socket.closes, 1);
});

test('cancelling a pending manifest read cancels its owned stream before any socket', async () => {
  const abort = new AbortController(); let cancelled = 0, sockets = 0;
  const trace = lifecycleTrace();
  let reading!: () => void;
  const started = new Promise<void>(resolve => { reading = resolve; });
  const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
    limits: limits(), signal: abort.signal, lifecycle: trace.producer, createSocket: () => { ++sockets; return new Socket(peer); },
    fetch: async () => new Response(new ReadableStream({
      pull() { reading(); }, cancel() { ++cancelled; },
    })),
  });
  await started; abort.abort(); await assert.rejects(pending, /cancel/i);
  assert.equal(cancelled, 1); assert.equal(sockets, 0);
  const terminal = trace.manifests[0]!.terminal; assert(terminal.kind === 'rejected');
  assert.deepEqual(terminal.value.response, {kind: 'received', body: {kind: 'not-complete'}});
  assert.equal(trace.exchanges.length, 0);
});

test('closed v1 discovery and rejected raw replies remain observable without becoming selections', async () => {
  for (const mutate of [
    (m: ReturnType<typeof manifest>) => ({ ...m, extra: true }),
    (m: ReturnType<typeof manifest>) => ({ ...m, providers: [{ ...m.providers[0]!, kind: 'unknown' }] }),
    (m: ReturnType<typeof manifest>) => ({ ...m, initialSources: [{ ...root, locator: 'bad\u0000locator' }] }),
    (m: ReturnType<typeof manifest>) => ({ ...m, initialSources: [{ ...root, providerId: 'unknown' }] }),
  ]) {
    const f = fixture({ manifestRaw: JSON.stringify(mutate(manifest())) });
    await assert.rejects(f.open()); assert.equal(f.counts().sockets, 0);
  }
  const raw = '{"jsonrpc":"2.0","id":1.0,"result":{"protocolVersion":1}}';
  const f = fixture({ respond: () => raw }); await assert.rejects(f.open());
  const exchange = f.observations.find(event => event.kind === 'exchange');
  assert.equal(exchange?.kind === 'exchange' ? exchange.reply : undefined, raw);
  assert.equal(f.socket.closes, 1);
});

test('capture options are read once before validation and the same values are sent', async () => {
  const f = fixture(); const opened = await f.open();
  if (opened.kind !== 'ready') throw new Error('Missing session');
  const projects = await opened.session.openSource(opened.session.sources[0]!);
  let scopes = 0, semantics = 0;
  await opened.session.exchangeCapture(projects[0]!, {
    get scope(): 'primary' { return ++scopes === 1 ? 'primary' : 'everything' as never; },
    get semantic(): 'none' { return ++semantics === 1 ? 'none' : 'unchecked' as never; },
  });
  assert.deepEqual((JSON.parse(f.socket.requests[2]!) as Request).params, {
    contractVersion: version, source: { providerId: root.providerId, locator: root.locator },
    projectId: project.id, scope: 'primary', semantic: 'none',
  });
  assert.equal(scopes, 1); assert.equal(semantics, 1); opened.session.close();
});

test('a manifest limit getter cannot change the stored validated budget', () => {
  let reads = 0;
  const limit = ModelOriginalsConnectionLimits.create({
    get manifestBytes() { return ++reads <= 3 ? 128 : Infinity; },
  });
  assert.equal(limit.manifestBytes, 128); assert.equal(reads, 1);
});

test('runtime construction and overridden limit getters cannot bypass the byte budget', async () => {
  assert.throws(() => Reflect.construct(ModelOriginalsConnectionLimits, [Infinity]));
  const genuine = ModelOriginalsConnectionLimits.create({ manifestBytes: 1 });
  let reads = 0, sockets = 0;
  const pending = openModelOriginalsSession(new URL('http://morphir.local'), {
    get limits() { return ++reads === 1 ? genuine : { manifestBytes: Infinity } as ModelOriginalsConnectionLimits; },
    signal: new AbortController().signal,
    fetch: async () => new Response(JSON.stringify(manifest())),
    createSocket: () => { ++sockets; return new Socket(peer); },
  });
  await assert.rejects(pending, /byte limit/i); assert.equal(reads, 1); assert.equal(sockets, 0);
});

test('a caller URL mutation during discovery cannot change the captured socket origin', async () => {
  const base = new URL('http://morphir.local/workbench'), socket = new Socket(peer);
  const opened = await openModelOriginalsSession(base, {
    limits: limits(), signal: new AbortController().signal,
    fetch: async input => {
      assert.equal(String(input), 'http://morphir.local/api/session');
      base.href = 'https://elsewhere.test/';
      return Response.json(manifest());
    }, createSocket: url => { assert.equal(url, 'ws://morphir.local/rpc'); return socket; },
  });
  if (opened.kind !== 'ready') throw new Error('Missing session');
  opened.session.close();
});
