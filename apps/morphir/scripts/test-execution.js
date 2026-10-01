import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,existsSync,mkdirSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const repo=fileURLToPath(new URL('../../../',import.meta.url));
const app=join(repo,'apps/morphir');
const home=process.env.MOON_HOME;
const npmCli=process.env.npm_execpath || (process.platform==='win32'?join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'):null);
const npm=(args,cwd)=>execFileSync(npmCli?process.execPath:'npm',npmCli?[npmCli,...args]:args,{cwd,encoding:'utf8',maxBuffer:4*1024*1024});
assert.ok(home,'Supply pinned MOON_HOME');
const moon=join(home,'bin/moon');
const root=mkdtempSync(join(tmpdir(),'morphir-execution-test-'));
const run=(program,args,expected=0)=>{
  const result=spawnSync(program,args,{cwd:repo,encoding:'utf8',timeout:180000,maxBuffer:4*1024*1024});
  assert.equal(result.error,undefined);assert.equal(result.status,expected,result.stderr+'\n'+result.stdout);return result;
};
try {
  const fixture=JSON.parse(run(moon,['run','--target','js','pkgs/morphir-moonbit/acceptance']).stdout);
  const model=join(root,'model.json'), suite=join(root,'calls.ion'), binary=join(root,'calls.ionb');
  writeFileSync(model,fixture.invocationIR);writeFileSync(binary,Buffer.from(fixture.invocationSuite));
  writeFileSync(suite,'{profile:"morphir-invocations-v1",calls:[{id:"subtract",entry:"calls:main#subtract",arguments:[9007199254741035,9007199254740993]},{id:"boolean",entry:"calls:main#boolean",arguments:[false]},{id:"unit",entry:"calls:main#unit",arguments:[morphir_unit::null]}]}');
  const helper=join(app,'build-provider/execution.mjs');
  const dependencies=['finos/morphir-sdk=pkgs/morphir-sdk','finos/morphir-execution=pkgs/morphir-execution','moonrockz/ion=.mooncakes/moonrockz/ion','moonbitlang/x=.mooncakes/moonbitlang/x','moonbitlang/async=.mooncakes/moonbitlang/async'].flatMap(v=>['--dependency',v]);
  const options=['--home',home,...dependencies];
  run(moon,['build','--target','js']);run(moon,['build','--target','native']);
  const js=join(repo,'_build/js/debug/build/morphir/morphir/morphir.js');
  const native=join(repo,'_build/native/debug/build/morphir/morphir/morphir.exe');
  for(const [program,prefix] of [[process.execPath,[js]],[native,[]]]) {
    const log=join(root,prefix.length?'js.ionb':'native.ionb');
    const result=JSON.parse(run(program,[...prefix,'verify',model,'--suite',suite,'--execution-helper',helper,...options,'--log-file',log,'--json']).stdout);
    assert.equal(result.successful,true);assert.equal(result.calls[0].actual.value,'42');assert.equal(result.calls[1].actual.value,false);assert.equal(result.calls[2].actual.type,'unit');
    assert.deepEqual([...readFileSync(log).subarray(0,4)],[0xe0,1,0,0xea]);
    assert.ok(!existsSync(result.evidence.executable),'Disposed session retains executable');
    const dry=join(root,'dry-log');
    const plan=JSON.parse(run(program,[...prefix,'verify',model,'--suite',suite,'--dry-run','--log-file',dry,'--json']).stdout);
    assert.equal(plan.dryRun,true);assert.ok(!existsSync(dry));
    const invalid=join(root,'invalid.ion');writeFileSync(invalid,'{profile:"morphir-invocations-v1",calls:[{id:"x",entry:"calls:main#private",arguments:[]}]}');
    assert.match(run(program,[...prefix,'verify',model,'--suite',invalid,'--json'],2).stderr,/entry_not_public_or_supported/);
  }
  const lines=run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,...options,'--log-file',join(root,'events.jsonl'),'--log-format','json-lines','--json-lines']).stdout.trim().split('\n').map(JSON.parse);
  assert.ok(lines.length>0);assert.ok(lines.every(l=>l.profile!=='morphir-observation-v1'));
  const events=readFileSync(join(root,'events.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.ok(events.some(e=>e.stage==='invoke'));assert.ok(events.every(e=>!JSON.stringify(e).includes('9007199254741035')));
  // A failing optional sink cannot alter parity or result framing.
  const failedSink=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',helper,...options,'--log-file',join(root,'absent','log.ionb'),'--json']).stdout);
  assert.equal(failedSink.successful,true);
  // Corrupt one real driver's typed result to prove the CLI mismatch exit status.
  const wrapper=join(root,'capture.mjs'),capture=join(root,'captured.json');
  writeFileSync(wrapper,`import {readFileSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';import {spawnSync} from 'node:child_process';
const request=JSON.parse(readFileSync(process.argv[2],'utf8'));
if(request.operation==='build')writeFileSync(${JSON.stringify(capture)},JSON.stringify(request));
const result=spawnSync(process.execPath,[${JSON.stringify(helper)},process.argv[2]],{encoding:'utf8',maxBuffer:4194304});
if(result.status===0&&request.operation==='invoke') {
 const file=join(dirname(process.argv[2]),'outcomes.ionb'),bytes=readFileSync(file);
 if(bytes.at(-2)!==0x21||bytes.at(-1)!==42)throw Error('Expected exact Ion integer 42');
 bytes[bytes.length-1]=43;writeFileSync(file,bytes);
}
process.stdout.write(result.stdout);process.stderr.write(result.stderr);process.exitCode=result.status;
`);
  const mismatch=JSON.parse(run(process.execPath,[js,'verify',model,'--suite',binary,'--execution-helper',wrapper,...options,'--json'],1).stdout);
  assert.equal(mismatch.successful,false);assert.equal(mismatch.calls[0].actual.value,'43');assert.equal(mismatch.calls[0].expected.value,'42');
  // Reuse a single retained executable for different runtime argument values.
  const lease=join(root,'reuse');mkdirSync(lease);
  const requestPath=join(lease,'request.json');
  const buildRequest={...JSON.parse(readFileSync(capture,'utf8')),leaseId:'reuse'};
  writeFileSync(requestPath,JSON.stringify(buildRequest));
  const built=JSON.parse(run(process.execPath,[helper,requestPath]).stdout);
  const executableBefore=readFileSync(built.executable);
  for(const input of [fixture.invocationSuite,fixture.invocationSuite2]) {
    const bytes=Buffer.from(input);writeFileSync(join(lease,'suite.ionb'),bytes);
    writeFileSync(requestPath,JSON.stringify({operation:'invoke',leaseId:'reuse',timeout:120000,suiteIdentity:createHash('sha256').update(bytes).digest('hex')}));
    run(process.execPath,[helper,requestPath]);
    assert.equal(readFileSync(join(lease,'outcomes.ionb')).at(-1),42);
    assert.deepEqual(readFileSync(built.executable),executableBefore);
  }
  rmSync(lease,{recursive:true});
  // Install the actual packed CLI, including its process helpers.
  const packed=JSON.parse(npm(['pack','--json','--pack-destination',root],app))[0];
  const install=join(root,'install');mkdirSync(install);
  npm(['install','--ignore-scripts','--no-audit','--no-fund','--offline','--prefix',install,join(root,packed.filename)],repo);
  const installed=join(install,'node_modules/@morphir/morphir');
  const output=JSON.parse(run(process.execPath,[join(installed,'bin/morphir.js'),'verify',model,'--suite',binary,'--execution-helper',join(installed,'build-provider/execution.mjs'),...options,'--json']).stdout);
  assert.equal(output.calls[0].actual.value,'42');assert.equal(output.successful,true);
  console.log(JSON.stringify({successful:true,hosts:['native','node','installed-npm'],target:'js',exactIntegers:true,bool:true,unit:true,ionLogs:true,jsonLines:true,dryRun:true,failedSink:true,cleanup:true,mismatchExit:true,driverReuse:true}));
} finally {rmSync(root,{recursive:true,force:true});}
