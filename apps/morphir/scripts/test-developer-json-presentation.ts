import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Build current artifacts once, then reuse them with a compiled MoonBit child
// fixture. No historical Git objects, shell shims, live tracker or acquisitions.
const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const root = realpathSync(mkdtempSync(join(tmpdir(), 'morphir developer JSON λ ')));
const names = ['beads-check', 'beads-companion', 'beads-plan', 'check', 'pre-push', 'refresh-ir-fixtures', 'repository-tasks', 'setup-hooks', 'typescript-tooling', 'validate-packages'];
const moon = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin', process.platform === 'win32' ? 'moon.exe' : 'moon') : 'moon';
const artifacts = new Map<string, string>();
const receipts: object[] = [];
function build(source: string, name: string): string {
  const target = join(root, 'build', name);
  const start = performance.now();
  const r = spawnSync(moon, ['build', source, '--target', 'native', '--target-dir', target], { cwd: repo, encoding: 'utf8', timeout: 120_000 });
  assert.equal(r.status, 0, `build ${name}: ${r.stdout}${r.stderr}`);
  const artifact = join(target, basename(source), 'native/debug/build/single/single.exe');
  assert.ok(existsSync(artifact), artifact);
  receipts.push({ build: name, status: r.status, milliseconds: performance.now() - start });
  return artifact;
}
const stubSource = `import {
  "moonbitlang/async@0.22.1",
  "moonbitlang/async@0.22.1/fs",
  "moonbitlang/async@0.22.1/stdio",
  "moonbitlang/core/env",
  "moonbitlang/core/json",
  "moonbitlang/x@0.5.5/sys",
}
async fn main {
  let argv = @env.args()
  let program = argv[0].replace(old="\\\\", new="/").split("/").last().unwrap().to_owned().replace(old=".exe", new="")
  let args = argv[1:].to_owned()
  let input = if @env.get_env_var("FIXTURE_READ_STDIN") == Some(program) { @stdio.stdin.read_all().text() } else { "" }
  let journal : Json = {"program":program,"args":Json::array(args.map(Json::string)),"cwd":@fs.realpath("."),"marker":@env.get_env_var("FIXTURE_MARKER").unwrap_or(""),"stdin":input}
  @fs.write_file(@env.get_env_var("FIXTURE_JOURNAL").unwrap(), journal.stringify() + "\\n", append=true, create_mode=@fs.OpenOrCreate)
  if program == "bd" && @env.get_env_var("FIXTURE_DESIGN_STATE") is Some(state) {
    match args {
      ["show", id, "--json"] => {
        let issue : Json = [{"id":id,"title":"Fixture","status":"open","design":@fs.read_file(state).text()}]
        @stdio.stdout.write(issue.stringify())
        return
      }
      ["update", _, "--design-file", source] => {
        @fs.write_file(state, @fs.read_file(source))
        return
      }
      _ => ()
    }
  }
  let responses = @fs.read_file(@env.get_env_var("FIXTURE_RESPONSES_FILE").unwrap()).json()
  guard responses is Array(items) else { fail("fixture responses must be an array") }
  for item in items {
    guard item is {"program":String(name),"args":wanted,"stdout":String(out),"stderr":String(err),"status":Number(code, ..),..} else { fail("invalid fixture response") }
    if name == program && (wanted is Null || wanted == Json::array(args.map(Json::string))) {
      @stdio.stdout.write(out)
      @stdio.stderr.write(err)
      @sys.exit(code.to_int())
    }
  }
  @stdio.stdout.write("child stdout λ\\n")
  @stdio.stderr.write("child stderr λ\\n")
}
`;
type Response = { program: string; args: string[] | null; stdout: string; stderr: string; status: number };
const response = (program: string, args: string[] | null, stdout: string, status = 0): Response => ({ program, args, stdout, stderr: '', status });
const bin = join(root, 'bin');
const cwd = join(root, 'cwd space λ');
const journal = join(root, 'journal.jsonl');
const responsesFile = join(root, 'responses.json');
mkdirSync(bin); mkdirSync(cwd);
let sequence = 0;
function invoke(name: string, args: string[], responses: Response[] = [], options: { status?: number; input?: string; env?: NodeJS.ProcessEnv; json?: boolean; cwd?: string } = {}) {
  writeFileSync(journal, '');
  writeFileSync(responsesFile, JSON.stringify(responses));
  const start = performance.now();
  const r = spawnSync(artifacts.get(name)!, args, { cwd: options.cwd ?? cwd, encoding: 'utf8', timeout: 30_000, input: options.input ?? '', env: { ...process.env, PATH: bin + delimiter + process.env.PATH, CI: '', GITHUB_ACTIONS: '', FIXTURE_JOURNAL: journal, FIXTURE_RESPONSES_FILE: responsesFile, FIXTURE_MARKER: 'inherited λ $;`', ...options.env } });
  const calls = readFileSync(journal, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  receipts.push({ id: ++sequence, command: name, args, responses, input: options.input ?? "", environment: options.env ?? {}, cwd: options.cwd ?? cwd, status: r.status, signal: r.signal, stdout: r.stdout, stderr: r.stderr, calls, milliseconds: performance.now() - start });
  assert.ifError(r.error);
  assert.equal(r.status, options.status ?? 0, `${name} ${JSON.stringify(args)}: ${r.stderr}\n${r.stdout}`);
  assert.equal(r.signal, null);
  let value: any;
  if (options.json !== false) {
    assert.ok(r.stdout.endsWith('\n') && !r.stdout.endsWith('\n\n'), r.stdout);
    assert.equal(r.stdout.split('\n').length, 2, r.stdout);
    value = JSON.parse(r.stdout);
    assert.equal(value.profile, 'morphir/command-result');
    assert.equal(value.contractVersion, '0.1.0');
    assert.equal(value.exitCode, options.status ?? 0);
    assert.equal(value.state, value.exitCode ? 'failed' : 'succeeded');
    assert.deepEqual(value.diagnostics, []);
    if (value.exitCode) { assert.ok(value.error.message); assert.equal(value.result, undefined); }
    else { assert.ok(value.result); assert.equal(value.error, undefined); }
  }
  return { ...r, calls, value };
}
try {
  for (const name of names) artifacts.set(name, build(join(repo, 'scripts', name + '.mbtx'), name));
  const source = join(root, 'child-fixture.mbtx'); writeFileSync(source, stubSource);
  const child = build(source, 'child-fixture');
  for (const name of ['git', 'bd', 'mise', 'moon', 'moonx', 'bun', 'node', 'yamllint', 'curl']) cpSync(child, join(bin, name + (process.platform === 'win32' ? '.exe' : '')));

  for (const name of names) {
    const r = invoke(name, ['--json', '--help']);
    assert.ok(r.value.result.help.includes('Usage:'));
    assert.deepEqual(r.calls, [], `${name} help had effects`);
  }
  assert.ok(invoke('beads-companion', ['--json']).value.result.help.includes('Usage:'));
  // JSON help uses the complete refresh grammar, including valid options.
  for (const args of [
    ['--json', '--morphir', 'missing checkout', '--help'],
    ['--json', '--help', '--morphir-elm=--json'],
    ['--json', '--morphir', '', '--morphir-elm', 'λ', '-h'],
    ['--json', '--self-test', '--help'],
  ]) {
    const r = invoke('refresh-ir-fixtures', args);
    assert.equal(r.value.command, 'refresh.ir.fixtures.help');
    assert.ok(r.value.result.help.includes('Usage:'));
    assert.deepEqual(r.calls, [], 'refresh help performed command effects');
  }
  invoke('refresh-ir-fixtures', ['--json', '--unknown', '--help'], [], { status: 2 });

  const tasks: Record<string, string[][]> = {
    build: [['run', 'build:wasi'], ['run', 'build:browser'], ['run', 'build:js'], ['run', 'build:native']],
    'build:wasi': [['build', '--target', 'wasm']], 'build:browser': [['build', '--target', 'wasm-gc']],
    'build:js': [['build', '--target', 'js']], 'build:native': [['build', '--target', 'native', '--release']],
    test: [['test', '--target', 'wasm'], ['test', '--target', 'wasm-gc'], ['test', '--target', 'js'], ['test', '--target', 'native'], ['run', 'test:cli'], ['run', 'test:compiler']],
    format: [['fmt']], 'lint:moonbit': [['fmt', '--check']], lint: [['run', 'lint:yaml'], ['run', 'lint:moonbit']],
    validate: [['run', 'lint:yaml'], ['run', 'validate:packages']], 'list-tasks': [['tasks']], clean: [['clean']], 'lint:yaml': [],
  };
  for (const [task, expected] of Object.entries(tasks)) {
    const r = invoke('repository-tasks', ['--json', task, '--json', '', 'λ', '--', '--ci']);
    assert.equal(r.value.result.task, task);
    if (task === 'list-tasks') assert.equal(r.value.result.listing, 'child stdout λ\n');
    assert.deepEqual(r.calls.map(x => x.args), expected);
    assert.ok(r.calls.every(x => x.cwd === cwd && x.marker === 'inherited λ $;`'));
  }
  writeFileSync(join(cwd, 'a λ.yaml'), 'fixture');
  const yaml = invoke('repository-tasks', ['--json', 'lint:yaml']);
  assert.deepEqual(yaml.value.result.yamlFiles, ['./a λ.yaml']);
  invoke('repository-tasks', ['--json', 'lint:yaml'], [response('yamllint', null, 'invalid YAML\n', 23)], { status: 23 });
  rmSync(join(cwd, 'a λ.yaml'));
  mkdirSync(join(cwd, '_build')); writeFileSync(join(cwd, '_build', 'artifact'), 'remove');
  const clean = invoke('repository-tasks', ['--json', 'clean'], [response('moon', null, 'ignored legacy failure\n', 23)]);
  assert.deepEqual(clean.value.result.removedPaths, ['./_build']); assert.ok(!existsSync(join(cwd, '_build')));
  for (const code of [23, 130]) {
    const r = invoke('repository-tasks', ['--json', 'build'], [response('mise', null, 'partial output\n', code)], { status: code });
    assert.equal(r.calls.length, 1);
    invoke('typescript-tooling', ['--json', 'setup-site'], [response('bun', null, 'partial output\n', code)], { status: code });
  }
  invoke('repository-tasks', ['--json', 'lint:moonbit'], [response('moon', null, 'bad format\n', 23)], { status: 1 });
  invoke('repository-tasks', ['--json', 'unknown'], [], { status: 1 });
  invoke('typescript-tooling', ['--json'], [], { status: 2 });
  invoke('typescript-tooling', ['--json', 'unknown'], [], { status: 2 });
  for (const task of ['setup-workbench', 'setup-site', 'build-workbench', 'test-workbench', 'test-workbench-artifacts', 'test-embedding', 'test-compiler', 'test-supervision', 'test-cli', 'check']) {
    const r = invoke('typescript-tooling', ['--json', task, '--', '--ci', '--json', '', 'λ']);
    assert.equal(r.value.result.task, task); assert.equal(r.value.result.ci, true);
    assert.ok(r.calls.length > 0);
    assert.deepEqual(r.value.result.steps.map((x: any) => [x.program, x.args, x.exitCode]), r.calls.map(x => [x.program, x.args, 0]));
  }
  const typescript = invoke('typescript-tooling', ['--json', 'setup-site', '--ci=true']);
  assert.equal(typescript.value.result.ci, false);
  const literalHelp = invoke('pre-push', ['--json', 'origin', '--help']);
  assert.equal(literalHelp.calls.length, 3);
  const stdin = 'refs/heads/topic 123 refs/heads/main 456\n';
  const push = invoke('pre-push', ['--json', 'origin', '--json', '--', '', 'λ'], [], { input: stdin, env: { FIXTURE_READ_STDIN: 'mise' } });
  assert.deepEqual(push.calls.map(x => x.args), [['run', 'lint'], ['run', 'lint:moonbit'], ['run', 'validate']]);
  assert.equal(push.calls[0].stdin, stdin);
  const pushFailure = invoke('pre-push', ['--json'], [response('mise', null, 'failure\n', 23)], { status: 1 });
  assert.equal(pushFailure.calls.length, 1);
  const check = invoke('check', ['--json']);
  assert.deepEqual(check.calls.map(x => x.args), [['run', 'lint'], ['run', 'test:ci'], ['run', 'test'], ['run', 'build']]);
  invoke('check', ['--json'], [response('mise', null, 'failure\n', 23)], { status: 23 });

  const hooks = join(root, 'hooks');
  const gitHooks = [response('git', ['rev-parse', '--path-format=absolute', '--git-path', 'hooks'], hooks + '\n')];
  const installed = invoke('setup-hooks', ['--json'], gitHooks);
  assert.equal(installed.value.result.outcome, 'installed');
  assert.ok(readFileSync(join(hooks, 'pre-push'), 'utf8').includes('exec mise exec -- moonx scripts/pre-push.mbtx "$@"'));
  assert.equal(invoke('setup-hooks', ['--json'], gitHooks).value.result.outcome, 'unchanged');
  writeFileSync(join(hooks, 'pre-push'), 'custom hook λ\n');
  assert.equal(invoke('setup-hooks', ['--json'], gitHooks).value.result.outcome, 'custom-preserved');
  assert.equal(readFileSync(join(hooks, 'pre-push'), 'utf8'), 'custom hook λ\n');
  const skip = invoke('setup-hooks', ['--json'], [], { env: { CI: 'true' } });
  assert.equal(skip.value.result.outcome, 'skipped'); assert.deepEqual(skip.calls, []);
  assert.equal(invoke('setup-hooks', ['--json'], [response('git', null, '', 23)]).value.result.outcome, 'skipped');

  // Fixture database only: the locator, count and design data never reach bd.
  const fixtureRepo = join(root, 'fixture-repo'); const database = join(fixtureRepo, '.beads');
  mkdirSync(join(database, 'embeddeddolt'), { recursive: true });
  const locator = [response('git', ['rev-parse', '--show-toplevel'], fixtureRepo + '\n'), response('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], fixtureRepo + '/.git\n'), response('bd', ['where', '--json'], JSON.stringify({ path: database })), response('bd', ['count', '--json'], '{"count":7}')];
  assert.equal(invoke('beads-check', ['--json'], locator).value.result.issueCount, 7);
  invoke('beads-check', ['--json'], [response('git', null, '', 23)], { status: 1 });
  const emptyCount = locator.map(x => x.program === 'bd' && x.args?.[0] === 'count' ? response('bd', x.args, '{"count":0}') : x);
  invoke('beads-check', ['--json'], emptyCount, { status: 1 });
  const id = 'fixture-1'; const design = '<html>λ <svg></svg></html>';
  const issue = JSON.stringify([{ id, title: 'Fixture', status: 'open', design }]);
  const tracker = [response('moonx', null, ''), response('bd', ['show', id, '--json'], issue), response('bd', ['where', '--json'], JSON.stringify({ path: database })), response('bd', null, '')];
  const inspect = invoke('beads-companion', ['--json', 'design', 'inspect', id], tracker, { json: false });
  assert.deepEqual(JSON.parse(inspect.stdout), { id, title: 'Fixture', status: 'open', hasDesign: true, designFormat: 'html', embeddedSvgCount: 1 });
  for (const literal of ['--json', '--replace', '--help', '--self-test', '--', '', 'λ $;`']) {
    // Fixed FILE slots preserve flags and punctuation. Empty FILE is a real
    // missing-file error, never a presentation switch.
    if (!literal) { invoke('beads-companion', ['--json', 'note', id, literal], tracker, { status: 1 }); continue; }
    writeFileSync(join(cwd, literal), 'content λ');
    const note = invoke('beads-companion', ['--json', 'note', id, literal], tracker);
    assert.equal(note.value.result.appended, true);
    assert.deepEqual(note.calls.at(-1).args, ['note', id, '--file', join(cwd, literal)]);
  }
  const out = join(cwd, 'export λ.html');
  const exported = invoke('beads-companion', ['--json', 'design', 'export', id, out], tracker);
  assert.equal(exported.value.result.path, out); assert.equal(readFileSync(out, 'utf8'), design);
  invoke('beads-companion', ['--json', 'design', 'export', id, out], tracker, { status: 1 });
  invoke('beads-companion', ['--json', 'design', 'export', id, out, '--replace'], tracker);
  const stored = invoke('beads-companion', ['--json', 'design', 'store', id, out], tracker);
  assert.equal(stored.value.result.outcome, 'unchanged');
  const state = join(root, 'design-state'); writeFileSync(state, '');
  const written = invoke('beads-companion', ['--json', 'design', 'store', id, out], tracker, { env: { FIXTURE_DESIGN_STATE: state } });
  assert.equal(written.value.result.outcome, 'written'); assert.equal(readFileSync(state, 'utf8'), design);
  const memory = join(cwd, 'memory'); writeFileSync(memory, '--json\nλ');
  const remembered = invoke('beads-companion', ['--json', 'remember', 'fixture-memory', memory], tracker);
  assert.equal(remembered.value.result.saved, true);
  assert.deepEqual(remembered.calls.at(-1).args, ['remember', '--key', 'fixture-memory', '--', '--json\nλ']);
  invoke('beads-companion', ['--json', 'design', 'inspect', '--json'], tracker, { status: 1 });
  const writer = join(root, 'writer'); mkdirSync(writer); writeFileSync(join(writer, 'state'), '');
  invoke('beads-companion', ['--json', '--self-test-write', writer, '--json']);
  assert.equal(readFileSync(join(writer, 'state'), 'utf8'), '--json');
  const unchanged = invoke('beads-companion', ['--json', '--self-test-write', writer, '--json']);
  assert.equal(unchanged.value.result.written, false); assert.equal(unchanged.value.result.outcome, 'unchanged');
  invoke('beads-companion', ['--json', '--self-test-write', writer, '--replace'], [], { status: 1 });

  const cache = join(root, 'cache'); const revision = 'd6b7cfa4cd614c85a087c009505c2856d5c73086';
  mkdirSync(join(cache, 'morphir/bd-plan', revision), { recursive: true });
  writeFileSync(join(cache, 'morphir/bd-plan', revision, 'bd-plan.ts'), 'fixture only');
  const tails = [[], ['--self-test'], ['--json', '--', 'λ', '', '--'], ['--forward-argv', '--', '--json', '--'], ['', 'λ', '--', '--', '--help', '--replace', '$;`\"']];
  for (const tail of tails) {
    const json = invoke('beads-plan', ['--json', '--', ...tail], [], { env: { XDG_CACHE_HOME: cache, FIXTURE_READ_STDIN: 'bun' }, input: stdin });
    assert.deepEqual(json.calls[0].args.slice(2), tail); assert.equal(json.calls[0].stdin, stdin);
    assert.equal(json.value.result.stdout.delivery, 'stderr');
    const raw = invoke('beads-plan', ['--forward-argv', '--', ...tail], [], { env: { XDG_CACHE_HOME: cache }, json: false });
    assert.deepEqual(raw.calls[0].args.slice(2), tail); assert.equal(raw.stdout, 'child stdout λ\n');
  }
  invoke('beads-plan', ['--json', '--', '--help'], [response('bun', null, 'upstream partial\n', 23)], { env: { XDG_CACHE_HOME: cache }, status: 23 });
  invoke('beads-plan', ['--json', '--', 'spec'], [], { env: { HOME: '', XDG_CACHE_HOME: '', LOCALAPPDATA: '', OS: '' }, status: 1 });

  invoke('validate-packages', ['--json'], [], { status: 1 });
  const validation = invoke('validate-packages', ['--json'], [], { cwd: repo });
  assert.equal(validation.value.result.valid, true); assert.equal(validation.value.result.members.length, 20);
  // Generate only in a disposable tree; the formatter is the compiled fixture.
  const destination = 'pkgs/morphir-ir/conformance';
  mkdirSync(join(cwd, destination), { recursive: true });
  cpSync(join(repo, destination, 'fixtures'), join(cwd, destination, 'fixtures'), { recursive: true });
  const refresh = invoke('refresh-ir-fixtures', ['--json']);
  assert.equal(refresh.value.result.formatted, true);
  assert.equal(refresh.value.result.writtenFiles.length, 5);
  for (const path of refresh.value.result.writtenFiles) assert.ok(existsSync(join(cwd, path)));
  const elmPin = 'bc99af69a8b24d391311fae3822a87eafef3c334';
  const elmSource = '--json';
  const elmResponses = [1, 2].map(version => response('git', ['-C', elmSource, 'show', `${elmPin}:tests-integration/cli/test-data/rentals/expected-morphir-ir${version === 1 ? '-v1' : ''}.json`], readFileSync(join(repo, destination, `fixtures/v${version}-rentals.json`), 'utf8')));
  const refreshed = invoke('refresh-ir-fixtures', ['--json', '--morphir-elm=--json'], elmResponses);
  assert.equal(refreshed.value.result.refreshedFixtures.length, 2);
  invoke('refresh-ir-fixtures', ['--json', '--morphir=--json'], [response('git', null, '', 23)], { status: 1 });
  invoke('refresh-ir-fixtures', ['--json', '--morphir'], [], { status: 2 });
  invoke('refresh-ir-fixtures', ['--json'], [response('moon', null, 'formatter failure\n', 23)], { status: 23 });

  // Default success bytes and ignored foreign tails are independently specified.
  const defaultCheck = invoke('check', ['--forward-argv', '--', '--json'], [], { json: false });
  assert.equal(defaultCheck.stdout, 'child stdout λ\n'.repeat(4) + ['lint', 'test:ci', 'test', 'build'].map(task => `Checking ${task}\n`).join('') + 'All checks passed.\n');
  // Only the complete reserved prefix changes forwarding. An incomplete
  // spelling remains legacy ignored data, as it was before JSON support.
  const ignoredControl = invoke('check', ['--forward-argv'], [], { json: false });
  assert.equal(ignoredControl.stdout, defaultCheck.stdout);
  assert.deepEqual(ignoredControl.calls, defaultCheck.calls);
  const legacyHooks = join(root, 'legacy-hooks');
  const ignoredHookControl = invoke('setup-hooks', ['--forward-argv'], [response('git', ['rev-parse', '--path-format=absolute', '--git-path', 'hooks'], legacyHooks + '\n')], { json: false });
  assert.equal(ignoredHookControl.status, 0);
  assert.ok(readFileSync(join(legacyHooks, 'pre-push'), 'utf8').includes('managed pre-push dispatcher'));

  const defaultTs = invoke('typescript-tooling', ['setup-site', '--json', '--', '--ci'], [], { json: false });
  assert.equal(defaultTs.stdout, 'child stdout λ\n'.repeat(4));
  assert.ok(defaultTs.calls.at(-1).args.includes('--with-deps'));
  console.log(`Developer JSON presentation: ${sequence} explicit-argv cases passed on ${process.platform}/${process.arch}, native process runtime.`);
} finally {
  if (process.env.DEVELOPER_JSON_RECEIPTS) writeFileSync(process.env.DEVELOPER_JSON_RECEIPTS, JSON.stringify({ platform: process.platform, arch: process.arch, root, artifacts: Object.fromEntries(artifacts), receipts }, null, 2) + '\n');
  if (!process.env.DEVELOPER_JSON_KEEP_FIXTURE) rmSync(root, { recursive: true, force: true });
}
