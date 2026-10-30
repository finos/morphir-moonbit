// Fixture worker for the process launcher conformance suite. It speaks
// Content-Length framed JSON-RPC on stdin and stdout. The protocol is in
// pkgs/morphir-host/worker/process/conformance/README.md.
import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';

const args = process.argv.slice(2);
const ignoresExit = args.includes('--ignore-exit');
// A worker that ignores exit also outlives the end of its stdin.
if (ignoresExit) setInterval(() => {}, 1000);
let grandchild = null;
if (args.includes('--grandchild')) {
  // The grandchild stays in the worker's process group and tree.
  grandchild = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    stdio: 'ignore',
    windowsHide: true,
  });
}

function send(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function reply(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function stop() {
  if (!ignoresExit) process.exit(0);
}

function handle(message) {
  const { id, method, params } = message;
  if (id === undefined) {
    if (method === 'exit') stop();
    return;
  }
  switch (method) {
    case 'echo':
      return reply(id, params ?? null);
    case 'argv':
      return reply(id, { args });
    case 'env':
      return reply(id, { names: Object.keys(process.env).sort() });
    case 'cwd':
      return reply(id, { entries: readdirSync(process.cwd()).length });
    case 'pids':
      return reply(id, { worker: process.pid, grandchild: grandchild?.pid ?? null });
    case 'hang':
      return;
    case 'stderr': {
      const size = params?.bytes ?? 0;
      const chunk = Buffer.alloc(65536, 'e');
      let left = size;
      const next = () => {
        while (left > 0) {
          const part = left >= chunk.length ? chunk : chunk.subarray(0, left);
          left -= part.length;
          if (!process.stderr.write(part)) return process.stderr.once('drain', next);
        }
        process.stderr.write('\nstderr end\n', () => reply(id, { written: size }));
      };
      return next();
    }
    case 'log':
      process.stdout.write('worker log line\r\n\r\n');
      return;
    case 'oversized':
      process.stdout.write('Content-Length: 16777217\r\n\r\n');
      return;
    case 'crash':
      process.exit(3);
      return;
    default:
      return send({ jsonrpc: '2.0', id, error: { code: -32601, message: `unknown method ${method}` } });
  }
}

let input = Buffer.alloc(0);
process.stdin.on('data', (chunk) => {
  input = Buffer.concat([input, chunk]);
  for (;;) {
    const end = input.indexOf('\r\n\r\n');
    if (end < 0) return;
    const header = input.subarray(0, end).toString('utf8');
    const match = /^Content-Length: *(\d+)$/im.exec(header);
    if (!match) process.exit(2);
    const length = Number(match[1]);
    if (input.length < end + 4 + length) return;
    const body = input.subarray(end + 4, end + 4 + length).toString('utf8');
    input = input.subarray(end + 4 + length);
    handle(JSON.parse(body));
  }
});
process.stdin.on('end', stop);
