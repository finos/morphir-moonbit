// OFFGRAPH prospective product adapter controls. No implementation or execution.
// Install beside artifact-download.test.ts only after root reviews the packet.
// Synthetic inputs exercise storage/effects, never receiver/source authority.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {unzipSync} from 'fflate';
import {
  createOriginalsArchive, prepareOriginalsArchive,
  type OriginalArchiveInput, type OriginalArchiveEvent,
  type OriginalArchiveOperation, type ReadyOriginalArchive,
} from './originals-archive.ts';
import {CheckedArchiveWriter} from './originals-archive-storage.ts';

type Row = {kind: 'file'; path: string; bytes: Uint8Array} | {kind: 'directory'; path: string};
const utf8 = new TextEncoder();
function input(rows: readonly Row[], copied?: () => void): OriginalArchiveInput {
  return {
    kind: 'connected', entries: rows.length,
    rawBytes: rows.reduce((sum, row) => sum + (row.kind === 'file' ? row.bytes.byteLength : 0), 0),
    archiveNameBytes: rows.reduce((sum, row) => sum + utf8.encode(row.path + (row.kind === 'directory' ? '/' : '')).byteLength, 0),
    describe(sink) {for (const row of rows) row.kind === 'file' ? sink.file(row.path, row.bytes.byteLength) : sink.directory(row.path);},
    copyFiles(sink) {copied?.(); for (const row of rows) if (row.kind === 'file') sink.file(row.path, row.bytes);},
  };
}
function prepared(value: OriginalArchiveInput): OriginalArchiveOperation {
  const result = createOriginalsArchive(value);
  assert.equal(result.kind, 'prepared');
  if (result.kind !== 'prepared') throw new Error('expected an actual prepared operation');
  return result.operation;
}
async function bounded<T>(promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {return await Promise.race([promise, new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error('actual adapter settlement exceeded test deadline')), 10000);
  })]);} finally {clearTimeout(timer);}
}
async function ready(operation: OriginalArchiveOperation): Promise<ReadyOriginalArchive> {
  let receive!: (event: OriginalArchiveEvent) => void;
  const result = new Promise<OriginalArchiveEvent>(resolve => {receive = resolve;});
  prepareOriginalsArchive(operation, receive);
  const event = await bounded(result);
  assert.equal(event.kind, 'ready'); assert.equal(event.operation, operation);
  if (event.kind !== 'ready') throw new Error('real writer must finish successfully');
  await bounded(operation.whenSettled());
  return event.archive;
}
// Actual Blob and actual URL allocation are observed through their existing
// platform methods. Only the DOM link is a unit-test stand-in. This is not a
// browser download, task join, or platform allocation qualification.
async function downloadBytes(archive: ReadyOriginalArchive): Promise<Uint8Array> {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'document');
  const create = URL.createObjectURL, revoke = URL.revokeObjectURL;
  let blob: Blob | undefined, actualUrl: string | undefined, clicks = 0, removals = 0;
  Object.defineProperty(globalThis, 'document', {configurable: true, value: {
    createElement(name: string) {assert.equal(name, 'a'); return {href: '', download: '', click() {++clicks;}, remove() {++removals;}};},
    body: {append() {}},
  }});
  URL.createObjectURL = object => {assert(object instanceof Blob); blob = object; actualUrl = create(object); return actualUrl;};
  try {
    assert.equal(archive.requestDownload().kind, 'download-requested');
    assert.equal(archive.requestDownload().kind, 'retired');
    assert.equal(clicks, 1); assert.equal(removals, 1); assert(blob);
    return new Uint8Array(await blob.arrayBuffer());
  } finally {
    archive.dispose();
    URL.createObjectURL = create;
    if (actualUrl) revoke(actualUrl);
    if (descriptor) Object.defineProperty(globalThis, 'document', descriptor);
    else Reflect.deleteProperty(globalThis, 'document');
  }
}

test('S01 synchronous snapshot owns copies before deferred encoding and never exposes a raw Ready view', {timeout: 20000}, async () => {
  const suppliedCopy = new Uint8Array([239, 187, 191, 13, 10, 0, 255]);
  const expected = suppliedCopy.slice();
  const operation = prepared(input([{kind: 'file', path: 'opaque.bin', bytes: suppliedCopy}]));
  suppliedCopy.fill(42); // after synchronous create, before actual writer start
  try {
    const archive = await ready(operation);
    assert.equal(Reflect.has(archive, 'take'), false);
    assert.equal(Reflect.has(archive, 'bytes'), false);
    assert.deepEqual(unzipSync(await downloadBytes(archive))['opaque.bin'], expected);
  } finally {operation.retire(); await bounded(operation.whenSettled());}
});

test('S02 complete namespace validation refuses before requesting any raw file copies', () => {
  const conflicts: readonly (readonly Row[])[] = [
    [{kind: 'file', path: 'ok.bin', bytes: new Uint8Array([1])}, {kind: 'directory', path: '../outside'}],
    [{kind: 'directory', path: 'same'}, {kind: 'directory', path: 'same'}],
    [{kind: 'directory', path: 'same'}, {kind: 'file', path: 'same', bytes: new Uint8Array()}],
    [{kind: 'file', path: 'a', bytes: new Uint8Array()}, {kind: 'file', path: 'a/b', bytes: new Uint8Array()}],
    [{kind: 'file', path: 'Root/a', bytes: new Uint8Array()}, {kind: 'directory', path: 'root'}],
    [{kind: 'directory', path: 'aux'}], [{kind: 'directory', path: 'bad\ud800'}],
  ];
  for (const rows of conflicts) {
    let copyCalls = 0;
    const result = createOriginalsArchive(input(rows, () => {++copyCalls;}));
    assert.equal(result.kind, 'refused');
    if (result.kind === 'refused') assert.equal(result.failure.kind, 'inventory');
    assert.equal(copyCalls, 0);
  }
});

test('S03 directory-only archives preserve every explicit directory and omit implicit ancestors', {timeout: 20000}, async () => {
  const operation = prepared(input([{kind: 'directory', path: 'parent/leaf'}, {kind: 'directory', path: 'empty'}]));
  try {
    const files = unzipSync(await downloadBytes(await ready(operation)));
    assert.deepEqual(Object.keys(files).sort(), ['empty/', 'parent/leaf/']);
    for (const bytes of Object.values(files)) assert.equal(bytes.length, 0);
  } finally {operation.retire(); await bounded(operation.whenSettled());}
});

test('S04 an implicit parent may become the same exact explicit directory', {timeout: 20000}, async () => {
  const operation = prepared(input([{kind: 'file', path: 'parent/child', bytes: new Uint8Array([7])}, {kind: 'directory', path: 'parent'}]));
  try {
    const files = unzipSync(await downloadBytes(await ready(operation)));
    assert.deepEqual(Object.keys(files).sort(), ['parent/', 'parent/child']);
    assert.deepEqual(files['parent/child'], new Uint8Array([7]));
  } finally {operation.retire(); await bounded(operation.whenSettled());}
});

test('S05 connected combined entry admission accepts 100063/100064 and refuses one more before raw copy', async () => {
  const rows = Array.from({length: 100064}, (_, n): Row => ({kind: 'directory', path: `d${n}`}));
  for (const count of [100063, 100064]) {
    const operation = prepared(input(rows.slice(0, count)));
    operation.retire(); await bounded(operation.whenSettled());
  }
  let copyCalls = 0;
  const result = createOriginalsArchive(input([...rows, {kind: 'file', path: 'extra', bytes: new Uint8Array()}], () => {++copyCalls;}));
  assert.equal(result.kind, 'refused'); assert.equal(copyCalls, 0);
});

test('S06 connected raw admission accepts 64MiB minus one/exact and refuses one more before raw copy', async () => {
  const raw = new Uint8Array(64 * 1024 * 1024);
  for (const bytes of [raw.slice(0, raw.length - 1), raw]) {
    const operation = prepared(input([{kind: 'file', path: 'raw.bin', bytes}]));
    operation.retire(); await bounded(operation.whenSettled());
  }
  let copyCalls = 0;
  const result = createOriginalsArchive(input([{kind: 'file', path: 'raw.bin', bytes: raw}, {kind: 'file', path: 'extra', bytes: new Uint8Array([1])}], () => {++copyCalls;}));
  assert.equal(result.kind, 'refused'); assert.equal(copyCalls, 0);
});

test('S07 retire before deferred start cannot perform even the first actual sink write', async () => {
  const operation = prepared(input([{kind: 'file', path: 'one', bytes: new Uint8Array([1])}]));
  const write = CheckedArchiveWriter.prototype.writeUint8Array;
  let writes = 0; const events: OriginalArchiveEvent[] = [];
  CheckedArchiveWriter.prototype.writeUint8Array = async function(chunk) {++writes; return write.call(this, chunk);};
  try {
    operation.retire(); prepareOriginalsArchive(operation, event => events.push(event));
    await bounded(operation.whenSettled());
    assert.equal(writes, 0); assert.equal(events.some(event => event.kind === 'ready'), false);
  } finally {CheckedArchiveWriter.prototype.writeUint8Array = write; operation.retire(); await bounded(operation.whenSettled());}
});

test('S08 retire during an actual held sink write retains the real encoding settlement until released', {timeout: 20000}, async () => {
  const operation = prepared(input([{kind: 'file', path: 'one', bytes: new Uint8Array([1])}]));
  const write = CheckedArchiveWriter.prototype.writeUint8Array;
  let entered!: () => void, release!: () => void;
  const actualEntry = new Promise<void>(resolve => {entered = resolve;});
  const gate = new Promise<void>(resolve => {release = resolve;});
  let held = false, settled = false; const events: OriginalArchiveEvent[] = [];
  CheckedArchiveWriter.prototype.writeUint8Array = async function(chunk) {
    if (!held) {held = true; entered(); await gate;}
    return write.call(this, chunk);
  };
  try {
    prepareOriginalsArchive(operation, event => events.push(event));
    await bounded(actualEntry);
    operation.retire();
    const actualSettlement = operation.whenSettled().then(() => {settled = true;});
    await Promise.resolve(); await Promise.resolve();
    assert.equal(settled, false, 'actual writer call is still held, so operation must not report settlement');
    release(); await bounded(actualSettlement);
    assert.equal(events.some(event => event.kind === 'ready'), false);
  } finally {
    release(); operation.retire(); await bounded(operation.whenSettled());
    CheckedArchiveWriter.prototype.writeUint8Array = write;
  }
});
