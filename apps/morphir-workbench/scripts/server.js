import { createServer, request as forwardRequest } from 'node:http';
import { readFile } from 'node:fs/promises';

export function hostOrigin(value) {
  if (!value) return null;
  const host = new URL(value);
  if (host.protocol !== 'http:' || host.hostname !== '127.0.0.1' || !host.port || host.pathname !== '/' || host.search || host.hash || host.username || host.password) {
    throw new Error('MORPHIR_WORKBENCH_HOST_URL must be http://127.0.0.1:<port> with no path, query or credentials.');
  }
  return host;
}

export function createWorkbenchServer({ root = new URL('../dist/', import.meta.url), host = null } = {}) {
  const upstream = hostOrigin(host);
  const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml' };
  let authority;
  const allowed = request => request.headers.host === authority &&
    (!request.headers.origin || request.headers.origin === `http://${authority}`) &&
    request.headers['sec-fetch-site'] !== 'cross-site';
  const server = createServer(async (request, response) => {
    if (!allowed(request) || !request.url.startsWith('/') || request.url.startsWith('//')) { response.writeHead(403).end('Invalid workbench origin.'); return; }
    if (request.method !== 'GET') { response.writeHead(405).end(); return; }
    let url;
    try { url = new URL(request.url, `http://${authority}`); } catch { response.writeHead(400).end(); return; }
    if (url.origin !== `http://${authority}`) { response.writeHead(403).end(); return; }
    if (upstream && ['/launch', '/api/session'].includes(url.pathname)) {
      const forwarded = forwardRequest(new URL(url.pathname + url.search, upstream), {
        headers: { Host: upstream.host, ...(request.headers.cookie ? { Cookie: request.headers.cookie } : {}) },
      }, result => {
        const headers = { 'Cache-Control': 'no-store', 'Content-Type': result.headers['content-type'] || 'text/plain' };
        if (result.headers['set-cookie']) headers['Set-Cookie'] = result.headers['set-cookie'];
        // The one-time launch token never becomes a persisted URL or log entry.
        if (result.statusCode >= 300 && result.statusCode < 400) headers.Location = '/?mode=connected';
        response.writeHead(result.statusCode, headers);
        result.pipe(response);
      });
      forwarded.setTimeout(10000, () => forwarded.destroy(new Error('Host timeout')));
      forwarded.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end('The Morphir host is unavailable.'); });
      request.on('aborted', () => forwarded.destroy());
      forwarded.end();
      return;
    }
    const file = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (!/^[a-zA-Z0-9-]+\.(html|css|js|svg)$/.test(file)) { response.writeHead(404).end(); return; }
    try {
      let content = await readFile(new URL(file, root));
      if (upstream && file === 'index.html') content = Buffer.from(content.toString().replace('</head>', '<meta name="morphir-host-mode" content="connected"></head>'));
      response.writeHead(200, { 'Content-Type': mime[file.slice(file.lastIndexOf('.'))], 'Cache-Control': 'no-store' });
      response.end(content);
    } catch { response.writeHead(404).end('Build the workbench with npm run build first.'); }
  });
  server.on('listening', () => { authority = `127.0.0.1:${server.address().port}`; });
  server.on('upgrade', (request, socket, head) => {
    if (!upstream || request.url !== '/rpc' || !allowed(request) || request.headers.origin !== `http://${authority}`) {
      socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
    }
    const headers = { Host: upstream.host, Origin: upstream.origin, Connection: 'Upgrade', Upgrade: 'websocket' };
    for (const name of ['cookie', 'sec-websocket-key', 'sec-websocket-version', 'sec-websocket-protocol', 'sec-websocket-extensions']) {
      if (request.headers[name]) headers[name] = request.headers[name];
    }
    const forwarded = forwardRequest(new URL('/rpc', upstream), { headers });
    forwarded.setTimeout(10000, () => forwarded.destroy(new Error('Host timeout')));
    forwarded.on('upgrade', (response, remote, remoteHead) => {
      forwarded.setTimeout(0);
      socket.write(`HTTP/1.1 ${response.statusCode} ${response.statusMessage}\r\n`);
      for (let i = 0; i < response.rawHeaders.length; i += 2) socket.write(`${response.rawHeaders[i]}: ${response.rawHeaders[i + 1]}\r\n`);
      socket.write('\r\n');
      if (remoteHead.length) socket.write(remoteHead);
      if (head.length) remote.write(head);
      socket.pipe(remote); remote.pipe(socket);
      remote.on('error', () => socket.destroy());
      remote.on('close', () => socket.destroy());
      socket.on('close', () => remote.destroy());
    });
    forwarded.on('response', response => {
      socket.end(`HTTP/1.1 ${response.statusCode} Host rejected WebSocket\r\nConnection: close\r\n\r\n`);
      response.resume();
    });
    forwarded.on('error', () => socket.destroy());
    socket.on('error', () => forwarded.destroy());
    socket.on('close', () => forwarded.destroy());
    forwarded.end();
  });
  return server;
}
