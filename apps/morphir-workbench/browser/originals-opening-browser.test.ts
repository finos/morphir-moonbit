import assert from 'node:assert/strict';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import type {AddressInfo} from 'node:net';
import {test} from 'node:test';
import {chromium} from 'playwright';
import {createWorkbenchServer} from '../scripts/server.ts';
import {inventoryDigest, type Entry} from '../../../pkgs/morphir-host/model-originals-client/originals.ts';

for (const interruption of ['none', 'pending-cancel', 'queued-cancel', 'queued-close'] as const)
test(`built originals page owns source/project opening and delivery: ${interruption}`, {timeout: 15000}, async () => {
  const original = Buffer.from('\ufeff# original\r\nformatVersion: 4\r\n');
  const shared = {profile: 'morphir/workbench/model-originals', contractVersion: '0.1.0-draft.1'};
  const sources = ['A', 'B'].map(id => ({providerId: 'provider', locator: `workspace:${id}`, displayName: 'Same source'}));
  const binding = {sessionId: 'session', source: {providerId: 'provider', locator: 'workspace:B'}, projectId: 'project-B'};
  const entries: Entry[] = [{kind: 'file', entryId: 'file', path: 'model.yaml', byteLength: original.length,
    sha256: createHash('sha256').update(original).digest('hex')}];
  const inventoryHash = createHash('sha256');
  const digest = inventoryDigest(entries, {update(bytes) {inventoryHash.update(bytes);}, hex() {return inventoryHash.digest('hex');}});
  const requests: {method: string; params: unknown}[] = [];
  let manifests = 0;
  let release!: () => void, requestedRelease!: () => void;
  const pendingRelease = new Promise<void>(resolve => {requestedRelease = resolve;});
  const host = Bun.serve({port: 0, hostname: '127.0.0.1', fetch(request, server) {
    if (new URL(request.url).pathname === '/api/session') { ++manifests; return Response.json({protocolVersion: 1, sessionId: 'session', webSocketPath: '/rpc',
      providers: [{id: 'provider', name: 'Fixture', kind: 'connected', status: 'available', capabilities: [
        {name: 'morphir/workspace/open', version: '1'}, {name: shared.profile, version: shared.contractVersion},
      ]}], initialSources: sources}); }
    if (server.upgrade(request)) return;
    return new Response('Not found', {status: 404});
  }, websocket: {message(socket, raw) {
    const request = JSON.parse(String(raw)) as {id: number; method: string; params: {source: typeof sources[number]; target: unknown}};
    requests.push(request);
    let result: unknown;
    switch (request.method) {
      case 'morphir.session.initialize': result = {protocolVersion: 1}; break;
      case 'morphir.workspace.open': result = {snapshot: {id: 'workspace', root: request.params.source, name: 'Fixture', state: 'open',
        configAnchor: null, projects: ['A', 'B'].map(id => ({id: `project-${id}`, name: 'Same project', state: 'unloaded'})),
        modelSources: [], knowledgeBaseSources: [], diagnostics: []}}; break;
      case 'morphir.model-originals.capture': result = {...shared, status: 'ready', binding, captureId: 'capture',
        coverage: {kind: 'complete', declaration: shared.contractVersion},
        origin: {kind: 'compiled', record: {byteLength: 100, sha256: '0'.repeat(64), schema: 1, task: 'compile', module: '',
          ir: {path: 'model.yaml', layout: 'single-file', format: 'yaml', version: 'v4'}}},
        primary: {kind: 'file', path: 'model.yaml'}, companions: [], sourceFormatVersion: {status: 'reported', release: '4.0.0'},
        projection: {status: 'not-requested'}, inventory: {entryCount: 1, fileCount: 1, directoryCount: 0, sourceByteLength: original.length, sha256: digest}}; break;
      case 'morphir.model-originals.inventory': result = {...shared, binding, captureId: 'capture', inventorySha256: digest,
        startIndex: 0, entries, next: {kind: 'complete'}}; break;
      case 'morphir.model-originals.read': result = {...shared, binding, captureId: 'capture', target: request.params.target,
        offset: 0, nextOffset: original.length, content: original.toString('base64')}; break;
      case 'morphir.model-originals.release': result = {...shared, captureId: 'capture', status: 'released'}; break;
      default: throw new Error(`Unexpected method ${request.method}`);
    }
    const reply = () => socket.send(JSON.stringify({jsonrpc: '2.0', id: request.id, result}));
    if (request.method.endsWith('.release')) {release = reply; requestedRelease();} else reply();
  }}});
  const server = createWorkbenchServer({host: host.url.origin});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    const errors: string[] = [], effects: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {if (/execution-core\.js|worker\.js/.test(request.url())) effects.push(request.url());});
    await page.goto(`http://127.0.0.1:${(server.address() as AddressInfo).port}/?mode=connected-originals`);
    await page.getByRole('status').filter({hasText: 'Choose a model source'}).waitFor();
    if (interruption === 'queued-cancel' || interruption === 'queued-close') await page.evaluate(() => {
      const original = globalThis.morphirWorkbench.openOriginals;
      Reflect.set(globalThis, '__originalsTakeCount', 0);
      globalThis.morphirWorkbench.openOriginals = (hash, receive) => original(hash, event => {
        if (event.kind !== 'received') {receive(event); return;}
        const take = event.stage.take.bind(event.stage);
        event.stage.take = adopt => {
          Reflect.set(globalThis, '__originalsTakeCount', Number(Reflect.get(globalThis, '__originalsTakeCount')) + 1);
          return take(adopt);
        };
        // Hold the actual private stage and callback. No test-created owner,
        // bytes, selections or successful application result is substituted.
        Reflect.set(globalThis, '__deliverOriginals', () => receive(event));
      });
    });
    assert.equal(await page.getByRole('button', {name: 'Connect model source', exact: true}).count(), 1);
    await page.getByRole('button', {name: 'Connect model source', exact: true}).click();
    await page.getByRole('button', {name: 'Same source', exact: true}).nth(1).click();
    await page.getByRole('button', {name: 'Same project', exact: true}).nth(1).click();
    await pendingRelease;
    assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
    if (interruption === 'none') {
      await page.getByRole('button', {name: 'Settings', exact: true}).click();
      await page.getByRole('radio', {name: 'Tabs', exact: true}).check();
      await page.getByRole('radio', {name: 'Dark', exact: true}).check();
      await page.keyboard.press('Escape');
      await page.getByRole('button', {name: 'Close model', exact: true}).waitFor();
      assert.equal(requests.filter(request => request.method.endsWith('.capture')).length, 1);
    }
    if (interruption === 'pending-cancel') {
      await page.getByRole('button', {name: 'Discard', exact: true}).click();
      await page.getByRole('status').filter({hasText: 'Model opening cancelled'}).waitFor();
    }
    release();
    if (interruption === 'queued-cancel' || interruption === 'queued-close') {
      await page.waitForFunction(() => Reflect.has(globalThis, '__deliverOriginals'));
      await page.getByRole('button', {name: interruption === 'queued-close' ? 'Close model' : 'Discard', exact: true}).click();
      await page.getByRole('status').filter({hasText: interruption === 'queued-close' ? 'Model closed' : 'Model opening cancelled'}).waitFor();
      await page.evaluate(() => Reflect.get(globalThis, '__deliverOriginals')());
    }
    if (interruption !== 'none') {
      await page.evaluate(() => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
      assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
      if (interruption === 'queued-cancel' || interruption === 'queued-close') assert.equal(await page.evaluate(() => Reflect.get(globalThis, '__originalsTakeCount')), 0);
      assert.equal(manifests, 1);
      assert.equal(await page.getByRole('button', {name: 'Connect model source', exact: true}).isEnabled(), true);
      assert.deepEqual(effects, []); assert.deepEqual(errors, []);
      return;
    }
    await page.getByRole('status').filter({hasText: 'Original files ready'}).waitFor();
    await page.getByText('Original IR 4.0.0', {exact: true}).waitFor();
    const download = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Download model.yaml', exact: true}).click();
    const stream = await (await download).createReadStream();
    assert(stream); const chunks: Buffer[] = []; for await (const chunk of stream) chunks.push(Buffer.from(chunk));
    assert.deepEqual(Buffer.concat(chunks), original);
    assert.deepEqual(requests.find(request => request.method.endsWith('.capture'))!.params, {
      contractVersion: shared.contractVersion, source: binding.source, projectId: 'project-B', scope: 'complete', semantic: 'none',
    });
    assert.deepEqual(requests.map(request => request.method), ['morphir.session.initialize', 'morphir.workspace.open',
      'morphir.model-originals.capture', 'morphir.model-originals.inventory', 'morphir.model-originals.read', 'morphir.model-originals.release']);
    await page.getByRole('button', {name: 'Close model', exact: true}).click();
    await page.getByRole('status').filter({hasText: 'Model closed'}).waitFor();
    assert.equal(await page.getByRole('button', {name: 'Download model.yaml', exact: true}).count(), 0);
    assert.equal(manifests, 1);
    await page.getByRole('button', {name: 'Settings', exact: true}).click();
    assert.equal(await page.getByRole('radio', {name: 'Tabs', exact: true}).isChecked(), true);
    assert.equal(await page.getByRole('radio', {name: 'Dark', exact: true}).isChecked(), true);
    assert.deepEqual(effects, []); assert.deepEqual(errors, []);
  } finally {
    await browser.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    await host.stop(true);
  }
});
