import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request as httpRequest } from 'node:http';
import { once } from 'node:events';
import { createWorkbenchServer, hostOrigin } from './server.js';

async function listen(server) {
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  return `http://127.0.0.1:${server.address().port}`;
}
const get = (url, headers) => fetch(url, { headers, redirect: 'manual' });

test('proxy target is an explicit loopback HTTP origin', () => {
  assert.equal(hostOrigin('http://127.0.0.1:3000').origin, 'http://127.0.0.1:3000');
  for (const url of ['https://127.0.0.1:3000', 'http://example.com:3000', 'http://127.0.0.1:3000/rpc', 'http://user:pass@127.0.0.1:3000', 'http://127.0.0.1:3000/?token=secret']) {
    assert.throws(() => hostOrigin(url), /must be/);
  }
});

test('launch cookie is exchanged through the proxy and private routes enforce the browser origin', async t => {
  const requests = [];
  const upstream = createServer((request, response) => {
    requests.push({ url: request.url, host: request.headers.host, cookie: request.headers.cookie });
    if (request.url === '/launch?token=one-use') {
      response.writeHead(303, { 'Set-Cookie': 'morphir_session_test=secret; HttpOnly; SameSite=Strict; Path=/', Location: '/' }).end();
    } else if (request.url === '/api/session' && request.headers.cookie === 'morphir_session_test=secret') {
      response.writeHead(200, { 'Content-Type': 'application/json' }).end('{"protocolVersion":1}');
    } else response.writeHead(401).end();
  });
  const target = await listen(upstream);
  const proxy = createWorkbenchServer({ host: target });
  const base = await listen(proxy);
  t.after(() => { proxy.closeAllConnections(); proxy.close(); upstream.closeAllConnections(); upstream.close(); });
  const launch = await get(`${base}/launch?token=one-use`);
  assert.equal(launch.status, 303); assert.equal(launch.headers.get('location'), '/?mode=connected');
  assert.match(launch.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/);
  const cookie = launch.headers.get('set-cookie').split(';')[0];
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie })).status, 200);
  assert.equal(requests[1].host, new URL(target).host);
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie, Origin: 'https://attacker.example' })).status, 403);
  assert.equal((await get(`${base}/api/session`, { Cookie: cookie, 'Sec-Fetch-Site': 'cross-site' })).status, 403);
  assert.equal(requests.length, 2);
  const wrongHost = await new Promise(resolve => {
    httpRequest(`${base}/api/session`, { headers: { Host: 'attacker.example' } }, response => { response.resume(); resolve(response.statusCode); }).end();
  });
  assert.equal(wrongHost, 403);
});

test('WebSocket proxy checks its own origin before rewriting the upstream Host and Origin', async t => {
  let observed;
  const upstream = createServer();
  upstream.on('upgrade', (request, socket) => {
    observed = request.headers;
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n');
    socket.on('data', data => socket.write(data));
    socket.on('error', () => {});
    socket.on('end', () => socket.destroy());
  });
  const target = await listen(upstream);
  const proxy = createWorkbenchServer({ host: target });
  const base = await listen(proxy);
  t.after(() => { proxy.close(); upstream.close(); });
  const open = origin => new Promise(resolve => {
    const request = httpRequest(`${base}/rpc`, { headers: {
      Connection: 'Upgrade', Upgrade: 'websocket', Origin: origin, Cookie: 'morphir_session_test=secret',
      'Sec-WebSocket-Key': 'a-test-key', 'Sec-WebSocket-Version': '13',
    } });
    request.on('upgrade', (response, socket) => resolve({ response, socket }));
    request.on('response', response => { response.resume(); resolve({ response }); });
    request.end();
  });
  assert.equal((await open('https://attacker.example')).response.statusCode, 403);
  assert.equal(observed, undefined);
  const { response, socket } = await open(base);
  assert.equal(response.statusCode, 101);
  assert.equal(observed.host, new URL(target).host);
  assert.equal(observed.origin, target);
  assert.equal(observed.cookie, 'morphir_session_test=secret');
  const data = once(socket, 'data'); socket.write('frame bytes');
  assert.equal(String((await data)[0]), 'frame bytes');
  socket.destroy();
});
