import { test } from 'node:test';
import assert from 'node:assert/strict';
import { VerifiedArtifactSet } from './verified-artifacts.ts';
import {
  captureArtifactGeneration, decodeArtifactGenerateReply, parseArtifactRequestId,
  selectArtifactTransferProfile,
} from './artifact-client/artifact-transfer.ts';

const abcDigest = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const ffDigest = 'a8100ae6aa1940d0b663bb31cd466142ebbdbd5187131b92d93818987832eb89';
function manifest(extra = false, kind = 'binary') {
  const selected = selectArtifactTransferProfile({ id: 'playground', status: 'available', capabilities: [
    { name: 'morphir/workbench/artifacts', version: '0.1.0-draft.1' },
  ] });
  if (!selected.ok) throw new Error(selected.error.code);
  const captured = captureArtifactGeneration(selected.value, { sessionId: 'session', target: 'fixture', irVersion: '4' });
  const id = parseArtifactRequestId(2);
  if (!captured.ok || !id.ok) throw new Error('Invalid fixture capture');
  const descriptors = [{ id: 'abc', path: 'src/abc.txt', kind: 'utf8-text', byteLength: 3, sha256: abcDigest }];
  if (extra) descriptors.push({ id: 'ff', path: 'data/ff.bin', kind, byteLength: 1, sha256: ffDigest });
  const decoded = decodeArtifactGenerateReply(JSON.stringify({ jsonrpc: '2.0', id: 2, result: {
    profile: 'morphir/workbench/artifacts', contractVersion: '0.1.0-draft.1', status: 'ready',
    sessionId: 'session', providerId: 'playground', generationId: 'generation',
    producer: { id: 'fixture', version: '1.0.0' }, target: 'fixture', irVersion: '4', artifacts: descriptors, diagnostics: [],
  } }), captured.value, id.value);
  if (!decoded.ok || decoded.value.status !== 'ready') throw new Error('Invalid fixture manifest');
  return decoded.value;
}

const sha256 = (bytes: ArrayBuffer) => crypto.subtle.digest('SHA-256', bytes);

test('complete verified files privately own their original bytes', async () => {
  const captured = manifest(true); const abc = new TextEncoder().encode('abc');
  const input = new Map([[captured.artifacts[0]!.id, abc], [captured.artifacts[1]!.id, new Uint8Array([255])]]);
  const verified = await VerifiedArtifactSet.verify(captured, input, { isCurrent: () => true });
  assert.equal(Object.isFrozen(verified), true); assert.equal(verified.manifest, captured);
  abc.fill(0); input.clear();
  assert.deepEqual([...verified.bytes(captured.artifacts[0]!.id)], [97, 98, 99]);
  const leaked = verified.bytes(captured.artifacts[1]!.id); leaked[0] = 0;
  assert.deepEqual([...verified.bytes(captured.artifacts[1]!.id)], [255]);
  assert.deepEqual(verified.preview(captured.artifacts[0]!.id), { kind: 'text', text: 'abc' });
  assert.deepEqual(verified.preview(captured.artifacts[1]!.id), { kind: 'binary' });
});

test('producer-declared text with invalid UTF-8 retains verified original bytes', async () => {
  const captured = manifest(true, 'utf8-text');
  const verified = await VerifiedArtifactSet.verify(captured, new Map([
    [captured.artifacts[0]!.id, new TextEncoder().encode('abc')],
    [captured.artifacts[1]!.id, new Uint8Array([255])],
  ]), { isCurrent: () => true });
  assert.deepEqual(verified.preview(captured.artifacts[1]!.id), { kind: 'invalid-utf8' });
  assert.deepEqual([...verified.bytes(captured.artifacts[1]!.id)], [255]);
});

test('missing, extra and wrong-length files fail before hashing', async () => {
  const captured = manifest(); const id = captured.artifacts[0]!.id;
  let hashes = 0;
  const effects = { isCurrent: () => true, digest: async (bytes: ArrayBuffer) => { ++hashes; return sha256(bytes); } };
  for (const input of [new Map(), new Map([[id, new Uint8Array(2)]]),
    new Map([[id, new Uint8Array(3)], [manifest(true).artifacts[1]!.id, new Uint8Array(1)]])]) {
    await assert.rejects(VerifiedArtifactSet.verify(captured, input, effects), /inventory|length/);
  }
  assert.equal(hashes, 0);
});

test('a digest mismatch refuses the complete set after a valid prefix', async () => {
  const captured = manifest(true);
  await assert.rejects(VerifiedArtifactSet.verify(captured, new Map([
    [captured.artifacts[0]!.id, new TextEncoder().encode('abc')],
    [captured.artifacts[1]!.id, new Uint8Array([254])],
  ]), { isCurrent: () => true }), /digest/);
});

test('input and digest-port mutations cannot change privately captured bytes', { timeout: 2000 }, async () => {
  const captured = manifest(); const id = captured.artifacts[0]!.id;
  const source = new TextEncoder().encode('abc');
  let deliver!: () => void;
  const ready = Promise.withResolvers<void>();
  const verifying = VerifiedArtifactSet.verify(captured, new Map([[id, source]]), {
    isCurrent: () => true,
    async digest(bytes) {
      const actual = await sha256(bytes);
      new Uint8Array(bytes).fill(0);
      return new Promise<ArrayBuffer>(resolve => { deliver = () => resolve(actual); ready.resolve(); });
    },
  });
  source.fill(0);
  await ready.promise;
  deliver();
  assert.deepEqual([...(await verifying).bytes(id)], [97, 98, 99]);
});

test('context replacement during hashing prevents a verified owner from escaping', async () => {
  const captured = manifest(); let current = true;
  const input = new Map([[captured.artifacts[0]!.id, new TextEncoder().encode('abc')]]);
  await assert.rejects(VerifiedArtifactSet.verify(captured, input, {
    isCurrent: () => current,
    async digest(bytes) { const digest = await sha256(bytes); current = false; return digest; },
  }), /obsolete/);
});

test('obsolete input and malformed digest results fail closed', async () => {
  const captured = manifest(); const input = new Map([[captured.artifacts[0]!.id, new TextEncoder().encode('abc')]]);
  await assert.rejects(VerifiedArtifactSet.verify(captured, input, { isCurrent: () => false }), /obsolete/);
  await assert.rejects(VerifiedArtifactSet.verify(captured, input, {
    isCurrent: () => true, digest: async () => new ArrayBuffer(31),
  }), /digest/);
});

test('context replacement takes precedence after a failed awaited digest', async () => {
  const captured = manifest(); let current = true;
  await assert.rejects(VerifiedArtifactSet.verify(captured,
    new Map([[captured.artifacts[0]!.id, new TextEncoder().encode('abc')]]), {
      isCurrent: () => current,
      async digest() { current = false; throw new Error('cryptographic effect failed'); },
    }), /obsolete/);
});

test('the verified owner constructor cannot bypass verification at runtime', () => {
  assert.throws(() => Reflect.construct(VerifiedArtifactSet, [Symbol(), manifest(), new Map()]), /verification/);
});
