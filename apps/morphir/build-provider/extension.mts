import { existsSync, lstatSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { supervised, supervisedBytes } from './supervision.mjs';
import { pinnedFileHash } from './identity.mjs';

/** The Node process host's module closure; the MoonBit CLI checks the same set. */
const hostModules = ['node-mep-cli.mjs', 'node-mep-stdio.mjs', 'node-mep-adapter.mjs', 'node-mep-worker.mjs',
  'mep-adapter.mjs', 'mep-frames.mjs', 'wasm-memory.mjs', 'node-artifacts.mjs', 'artifacts.mjs',
  'assembly.mjs', 'index.mjs', 'dist/bridge.mjs'];
const profile = 'morphir/cli/extension-command', contractVersion = '0.1.0-draft.1';
const executionProfile = { id: 'morphir/mep-bytes-v1/v1-draft', sha256: '6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6' };

interface ExtensionPin {
  contractVersion: typeof contractVersion; binding: 'core-wasm-process';
  executionProfile: typeof executionProfile;
  runtime: { name: 'node'; version: 'v24.22.0'; executable: string; sha256: string };
  host: { root: string; modules: Record<string, string> };
  artifact: { directory: string; wasmSha256: string; manifestSha256: string };
  origin: string;
}
interface ExtensionRequest {
  profile: typeof profile; contractVersion: typeof contractVersion; pin: ExtensionPin;
  requestFile: string; responseFile: string; workDirectory: string; timeout: number; cancelFile: string;
}
/** Process facts only. The MoonBit CLI decodes frames and decides the MEP outcome. */
export interface ExtensionReply {
  profile: typeof profile; contractVersion: typeof contractVersion;
  state: 'exited' | 'refused' | 'failed' | 'cancelled'; exitCode: number | null;
  stderr: string; workDirectoryEmpty: boolean; error?: string;
}

function check(value: unknown, code: string): asserts value { if (!value) throw Error(code); }
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function exact(value: Record<string, unknown>, fields: string[]) {
  return Object.keys(value).length === fields.length && fields.every(key => Object.hasOwn(value, key));
}
const digest = (value: unknown) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const path = (value: unknown) => typeof value === 'string' && isAbsolute(value) && value.length <= 4096 && !value.includes('\0');

function request(value: unknown): ExtensionRequest {
  check(record(value) && exact(value, ['profile','contractVersion','pin','requestFile','responseFile','workDirectory','timeout','cancelFile']) &&
    value.profile === profile && value.contractVersion === contractVersion, 'extension.invalid_request');
  const pin = value.pin;
  check(record(pin) && exact(pin, ['contractVersion','binding','executionProfile','runtime','host','artifact','origin']) &&
    pin.contractVersion === contractVersion, 'extension.invalid_pin');
  check(pin.binding === 'core-wasm-process', 'extension.unsupported_binding');
  check(record(pin.executionProfile) && exact(pin.executionProfile, ['id','sha256']) &&
    pin.executionProfile.id === executionProfile.id && pin.executionProfile.sha256 === executionProfile.sha256,
  'extension.unsupported_execution_profile');
  const { runtime, host, artifact } = pin;
  check(record(runtime) && exact(runtime, ['name','version','executable','sha256']) && runtime.name === 'node' &&
    path(runtime.executable) && digest(runtime.sha256), 'extension.invalid_pin');
  check(runtime.version === 'v24.22.0', 'extension.unsupported_runtime');
  check(record(host) && exact(host, ['root','modules']) && path(host.root) && record(host.modules) &&
    exact(host.modules, hostModules) && hostModules.every(name => digest((host.modules as Record<string, unknown>)[name])),
  'extension.incomplete_host_modules');
  check(record(artifact) && exact(artifact, ['directory','wasmSha256','manifestSha256']) && path(artifact.directory) &&
    digest(artifact.wasmSha256) && digest(artifact.manifestSha256), 'extension.invalid_pin');
  check(typeof pin.origin === 'string' && pin.origin.length > 0 && pin.origin.length <= 2048 && !pin.origin.includes('\0'), 'extension.invalid_pin');
  check(path(value.requestFile) && path(value.responseFile) && path(value.workDirectory) &&
    Number.isSafeInteger(value.timeout) && Number(value.timeout) >= 1 && Number(value.timeout) <= 594000 &&
    typeof value.cancelFile === 'string' && !value.cancelFile.includes('\0'), 'extension.invalid_request');
  return value as unknown as ExtensionRequest;
}

/** Every pinned byte the guest process can load: runtime, host closure and guest. */
function verifyIdentities(pin: ExtensionPin, tick: () => void, code: string) {
  const expect = (file: string, sha256: string, kind: string) =>
    check(pinnedFileHash(file, tick, `extension.${kind}`) === sha256, code);
  expect(pin.runtime.executable, pin.runtime.sha256, 'runtime');
  for (const name of hostModules) expect(join(pin.host.root, name), pin.host.modules[name]!, 'host_module');
  expect(join(pin.artifact.directory, 'model.wasm'), pin.artifact.wasmSha256, 'artifact');
  expect(join(pin.artifact.directory, 'manifest.ion'), pin.artifact.manifestSha256, 'artifact');
}

/** Effects only: identity checks, one supervised guest process and its bytes. */
export async function extensionCommand(value: unknown, interrupted: () => boolean = () => false): Promise<ExtensionReply> {
  let started = false, workDirectory = '';
  const empty = () => { try { return workDirectory !== '' && readdirSync(workDirectory).length === 0; } catch { return false; } };
  try {
    const config = request(value);
    workDirectory = config.workDirectory;
    const deadline = performance.now() + config.timeout;
    const cancelFile = config.cancelFile ? resolve(config.cancelFile) : '';
    const tick = () => {
      check(!interrupted() && (!cancelFile || !existsSync(cancelFile)), 'execution.cancelled');
      check(performance.now() < deadline, 'execution.deadline');
    };
    const remaining = () => Math.max(1, Math.floor(deadline - performance.now()));
    check(lstatSync(config.workDirectory).isDirectory() && empty(), 'extension.invalid_request');
    const stat = lstatSync(config.requestFile);
    check(stat.isFile() && stat.size <= 4194304, 'extension.request_limit');
    const input = readFileSync(config.requestFile);
    verifyIdentities(config.pin, tick, 'extension.identity_mismatch');
    // Confined environment: the guest needs no PATH, toolchain or user state.
    const env: NodeJS.ProcessEnv = process.platform === 'win32' ? { SystemRoot: process.env.SystemRoot } : {};
    const version = await supervised(config.pin.runtime.executable, ['--version'],
      { cwd: config.workDirectory, env, timeout: Math.min(remaining(), 10000), cancelFile, cancelled: interrupted });
    check(version.code === 0 && !version.signal && version.stdout.trim() === config.pin.runtime.version, 'extension.runtime_version_mismatch');
    tick();
    started = true;
    const guest = await supervisedBytes(config.pin.runtime.executable,
      [join(config.pin.host.root, 'node-mep-cli.mjs'), config.pin.artifact.directory],
      { cwd: config.workDirectory, env, timeout: remaining(), cancelFile, cancelled: interrupted, input });
    verifyIdentities(config.pin, () => {}, 'extension.identity_changed');
    check(!guest.signal, 'extension.guest_signalled');
    writeFileSync(config.responseFile, guest.stdout, { flag: 'wx', mode: 0o600 });
    return { profile, contractVersion, state: 'exited', exitCode: guest.code, stderr: guest.stderr, workDirectoryEmpty: empty() };
  } catch (cause) {
    const error = cause instanceof Error ? cause.message : 'extension.operation_failed';
    const cancelled = error.includes('execution.cancelled');
    return { profile, contractVersion, state: cancelled ? 'cancelled' : started ? 'failed' : 'refused',
      exitCode: null, stderr: '', workDirectoryEmpty: empty(), error };
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let result: ExtensionReply;
  try {
    check(process.argv.length === 4 && process.argv[2] === '--morphir-extension-v1', 'extension.invalid_control');
    const control = process.argv[3]!;
    const stat = lstatSync(control);
    check(stat.isFile() && stat.size <= 1048576, 'extension.invalid_control');
    result = await extensionCommand(JSON.parse(readFileSync(control, 'utf8')));
  } catch {
    result = { profile, contractVersion, state: 'refused', exitCode: null, stderr: '', workDirectoryEmpty: false, error: 'extension.invalid_control' };
  }
  // This is the private helper envelope, not the CLI's report format.
  process.stdout.write(JSON.stringify(result));
}
