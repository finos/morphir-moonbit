#!/usr/bin/env node
import * as fs from 'node:fs';

// Explicit runner for the CLI's WASI and WASM-GC artifacts.
const [artifact, ...args] = process.argv.slice(2);
if (!artifact) throw new Error('Usage: node wasm.mjs <artifact.wasm> [arguments]');
const module = await WebAssembly.compile(fs.readFileSync(artifact));
const imports = WebAssembly.Module.imports(module);
if (!imports.some(i => i.module === 'morphir_host_v1')) {
  const { WASI } = await import("node:wasi");
  const wasi = new WASI({version: 'preview1', args: ['morphir', ...args], env: process.env,
    preopens: {'.': process.cwd()}, returnOnExit: true});
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  process.exitCode = wasi.start(instance);
} else {
  const dispatch = (op, a, b) => {
    switch (op) {
      case 'args': return ['morphir', ...args];
      case 'environment': return process.env;
      case 'system_type': return process.platform === 'darwin' ? 'macos' : process.platform === 'win32' ? 'windows' : 'linux';
      case 'cwd': return process.cwd();
      case 'read': { if (fs.statSync(a).size > 16777216) throw new Error('File exceeds 16 MiB'); return new TextDecoder('utf-8', {fatal:true}).decode(fs.readFileSync(a)); }
      case 'write': return fs.writeFileSync(a, b);
      case 'list': return fs.readdirSync(a);
      case 'kind': {
        try { const s = fs.lstatSync(a); return s.isSymbolicLink() ? 3 : s.isDirectory() ? 2 : s.isFile() ? 1 : 4; }
        catch(e) { if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return 0; throw e; }
      }
      case 'mkdir': return fs.mkdirSync(a);
      case 'remove_file': return fs.unlinkSync(a);
      case 'remove_dir': return fs.rmdirSync(a);
      case 'rename': return fs.renameSync(a, b);
      case 'stderr': return void process.stderr.write(a);
      case 'exit': return void (process.exitCode = Number(a));
      default: throw new Error(`Unsupported host operation: ${op}`);
    }
  };
  const instance = await WebAssembly.instantiate(module, {
    morphir_host_v1: {
      begin: () => ({text: ''}), append: (s, c) => { s.text += String.fromCharCode(c); },
      length: s => s.text.length, at: (s, i) => s.text.charCodeAt(i),
      request: (op, a, b) => {
        try { return {text: JSON.stringify({value: dispatch(op.text, a.text, b.text) ?? null})}; }
        catch(e) { return {text: JSON.stringify({error: e.message})}; }
      },
    },
    spectest: { print_char: c => process.stdout.write(String.fromCharCode(c)) },
  });
  instance.exports._start();
}
