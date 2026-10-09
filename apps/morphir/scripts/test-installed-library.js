import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync,readFileSync,existsSync,rmSync,cpSync} from 'node:fs';
import {join,delimiter} from 'node:path';
import {capabilities} from '../build-provider/capabilities.mjs';
import {excluded,hash,treeIdentity} from '../build-provider/identity.mjs';
import {includeDependencyPath} from '../build-provider/paths.mjs';

const profile='moonbit-model-bool-library-v1';
const provider='finos/morphir-moonbit-frontend';

// The L1 fixture expectations are hand-authored, never computed from generated IR.
export function testInstalledLibrary({run,root,receipts,cli,helper,cwd,home,llvmHome,llvmPin,required,deps,pack,fixtures}) {
  assert.equal(fixtures.profile,profile);assert.equal(fixtures.language,'moonbit');
  assert.equal(fixtures.parserVersion,'0.4.1');
  assert.deepEqual(fixtures.models.map(m=>m.id),['forward','shadow','diamond','zero','private','operators']);
  assert.equal(fixtures.models.reduce((n,m)=>n+m.entries.length,0),13);
  assert.equal(fixtures.models.reduce((n,m)=>n+m.entries.reduce((n,e)=>n+e.expected.length,0),0),42);
  const output=join(receipts,'moonbit-library');mkdirSync(output,{recursive:true});
  rmSync(join(output,'summary.json'),{force:true});
  const call=(args,status=0,workdir=cwd)=>run(process.execPath,[cli,...args],{cwd:workdir,status});
  const compilers=new Map(required.map(target=>{
    const compilerHome=target==='llvm'?llvmHome:home;
    const toolchainPin=target==='llvm'?JSON.parse(readFileSync(llvmPin,'utf8')):undefined;
    const capability=capabilities({compilerHome,toolchainPin,timeout:10000});
    assert.ok(capability.targets.some(t=>t.target===target),'Required library lane unavailable: '+target);
    const env={...process.env,MOON_HOME:compilerHome,MOONBIT_NEW_NATIVE:'0',PATH:join(compilerHome,'bin')+delimiter+process.env.PATH};delete env.MOON_WORK;
    return [target,{compilerHome,capability,env}];
  }));
  const models=[],visibility=[];
  for(const model of fixtures.models) {
    const project=join(root,'library-'+model.id);mkdirSync(join(project,'src'),{recursive:true});
    const artifact=join(output,model.id);mkdirSync(artifact,{recursive:true});
    const manifest='[project]\nname="Library'+model.id[0].toUpperCase()+model.id.slice(1)+'"\nmodule_prefix="App"\n[frontend]\nlanguage="moonbit"\nprofile="'+profile+'"\n[pipeline]\nbackend="checkpoint"\ncomponents=["json-identity"]\n';
    const sourcePath=join(project,'src/Main.mbt');writeFileSync(join(project,'morphir.toml'),manifest);
    writeFileSync(sourcePath,'pub fn broken(');
    const dry=JSON.parse(call(['run','.','--dry-run','--log','--json'],0,project).stdout);
    const descriptor=dry.frontends[0];
    assert.equal(descriptor.language,'moonbit');assert.equal(descriptor.provider,provider);
    assert.equal(descriptor.profile,profile);assert.equal(descriptor.defaultProfile,false);
    assert.equal(descriptor.evidence,'local-acceptance');assert.equal(descriptor.outputContract,'ir-unit');
    assert.equal(descriptor.capabilities.maxDocuments,1);assert.equal(descriptor.capabilities.incremental,false);
    assert.ok(!existsSync(join(project,'.morphir')),'Library dry-run must not read source or create logs/output');
    writeFileSync(sourcePath,model.source);writeFileSync(join(artifact,'Main.mbt'),model.source);
    writeFileSync(join(artifact,'morphir.toml'),manifest);
    const compiled=JSON.parse(call(['run','.','--json'],0,project).stdout);
    assert.equal(compiled.successful,true);assert.equal(compiled.processed,1);
    const published=join(project,'.morphir/out/compile.dest');
    const checkpoint=join(artifact,'Main.ionb'),bytes=readFileSync(join(published,'Main.ionb'));
    assert.deepEqual([...bytes.subarray(0,4)],[224,1,0,234]);writeFileSync(checkpoint,bytes);
    assert.ok(!existsSync(join(project,'.morphir/logs')),'Logs remain disabled by default');
    assert.equal(JSON.parse(call(['run','.','--checkpoint-format','ion-text','--json'],0,project).stdout).successful,true);
    const ion=readFileSync(join(published,'Main.ion'),'utf8');
    for(const token of ['morphir_moonbit_frontend',profile,'moonbit-parser-position-v1','metadata','provenance'])assert.ok(ion.includes(token),token);
    for(const entry of [...model.entries,...model.private])assert.ok(ion.includes(entry.original.replaceAll('_','-')),entry.original);
    writeFileSync(join(artifact,'Main.ion'),ion);
    assert.equal(JSON.parse(call(['run','.','--backend','moonbit','--validation','source-only','--json'],0,project).stdout).successful,true);
    const generated=readFileSync(join(published,'Main/library.mbt'),'utf8');
    const generatedSnapshot=join(artifact,'generated');
    cpSync(join(published,'Main'),generatedSnapshot,{recursive:true});
    assert.equal((generated.match(/^pub fn /gm)||[]).length,model.entries.length);
    assert.equal((generated.match(/^fn /gm)||[]).length,model.private.length);
    writeFileSync(join(artifact,'library.mbt'),generated);
    const symbols=readFileSync(join(published,'Main/symbols.10n'));
    assert.deepEqual([...symbols.subarray(0,4)],[224,1,0,234]);writeFileSync(join(artifact,'symbols.10n'),symbols);
    const canonical=name=>'library-'+model.id+':app/main#'+name.replaceAll('_','-');
    const invocation=(names,file)=>{
      const suite=join(artifact,file);
      writeFileSync(suite,JSON.stringify({profile:'morphir-invocations-v1',calls:names.map(name=>({id:name,entry:canonical(name),arguments:[]}))}));
      return suite;
    };
    const rejectedEntries=[];
    for(const name of [...model.private.map(p=>p.original),'absent']) {
      const suite=invocation([name],'rejected-'+name+'.json');
      const rejection=JSON.parse(call(['execute',checkpoint,'--unit-id','Main','--suite',suite,'--dry-run','--json'],2).stdout);
      assert.match(rejection.error,/execution.entry_not_public_or_supported/);
      rejectedEntries.push(name);
    }
    const before=treeIdentity(published);
    const loss=JSON.parse(call(['run','.','--checkpoint-format','morphir-json','--json'],1,project).stdout);
    assert.match(loss.diagnostics[0].message,/data.lossy_conversion/);assert.deepEqual(loss.committed,[]);
    assert.equal(treeIdentity(published),before,'Lossy JSON rejection preserves all published artifacts');
    for(const [id,source,diagnostic] of [
      ['recursive','pub fn bad(x : Bool) -> Bool { bad(x) }',/moonbit_frontend\.recursive_call/],
      ['malformed','pub fn broken(',/moonbit_frontend\./],
      ['binding-type','pub fn bad() -> Bool { let x : Bool = 42; x }',/moonbit_frontend\./],
    ]) {
      writeFileSync(sourcePath,source);
      const failure=JSON.parse(call(['run','.','--json'],1,project).stdout);
      assert.equal(failure.successful,false);assert.deepEqual(failure.committed,[]);
      assert.match(failure.diagnostics[0].message,diagnostic);
      assert.match(failure.diagnostics[0].message,/provider finos\/morphir-moonbit-frontend; profile moonbit-model-bool-library-v1/);
      assert.equal(treeIdentity(published),before,'Rejected '+id+' preserves all published artifacts');
      writeFileSync(join(artifact,'rejected-'+id+'.json'),JSON.stringify(failure,null,2)+'\n');
    }
    writeFileSync(sourcePath,model.source);
    const rows=model.entries.flatMap(entry=>{
      assert.match(entry.original,/^[a-zA-Z_][a-zA-Z0-9_]*$/);
      assert.equal(entry.arguments.length,entry.expected.length);
      assert.equal(new Set(entry.arguments.map(args=>JSON.stringify(args))).size,entry.arguments.length);
      assert.equal(entry.arguments.length,2**entry.arguments[0].length,'Exhaustive Boolean rows');
      return entry.arguments.map((args,i)=>{
        assert.ok(args.every(a=>typeof a==='boolean'));assert.equal(typeof entry.expected[i],'boolean');
        return {id:entry.original+'-'+i,original:entry.original,entry:canonical(entry.original),arguments:args,expected:entry.expected[i]};
      });
    });
    const cases=join(artifact,'cases.ion');
    writeFileSync(cases,'{profile:"morphir-conformance-v1",version:"moonbit-library-bool-1",provenance:"Hand-authored exhaustive L1 Boolean rows; independently checked by the original compiler",cases:['+rows.map(r=>`{id:"${r.id}",entry:"${r.entry}",arguments:[${r.arguments}],expected:${r.expected}}`).join(',')+']}');
    const original=join(root,'library-original-'+model.id);mkdirSync(original);
    writeFileSync(join(original,'moon.mod'),'name="acceptance/library-original-'+model.id+'"\nversion="0.0.0"\n');
    writeFileSync(join(original,'moon.pkg'),'');writeFileSync(join(original,'Main.mbt'),model.source);
    writeFileSync(join(original,'original_test.mbt'),rows.map(r=>`///|\ntest "${r.id}" { assert_eq(${r.original}(${r.arguments.join(', ')}), ${r.expected}) }\n`).join('\n'));
    const verify=(target,mode,extra=[],status=0,suite=cases)=>call(['conform',checkpoint,'--unit-id','Main','--cases',suite,'--execution-helper',helper,'--home',target==='llvm'?llvmHome:home,...(target==='llvm'?['--toolchain-pin',llvmPin]:[]),...deps,'--target',target,'--build-mode',mode,...extra],status);
    const lanes=[];let baseline;
    for(const target of required)for(const mode of ['debug','release']) {
      const id=target+'-'+mode,{compilerHome,capability,env}=compilers.get(target);
      const oracle=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,...(mode==='release'?['--release']:[])],{cwd:original,env});
      assert.match(oracle.stdout,new RegExp(`Total tests: ${rows.length}, passed: ${rows.length}, failed: 0`));
      writeFileSync(join(artifact,id+'-original.log'),oracle.stdout+'\n'+oracle.stderr);
      // All-private libraries compile but have no public execution rows.
      if(rows.length===0)continue;
      const report=JSON.parse(verify(target,mode,['--receipt',join(artifact,id+'.ionb'),'--json']).stdout);
      assert.equal(report.successful,true);assert.equal(report.execution.calls.length,rows.length);
      assert.equal(report.execution.evidence.buildMode,mode);assert.equal(report.execution.target,target);
      assert.equal(report.execution.evidence.compilerIdentity,capability.compilerIdentity);
      assert.equal(report.execution.evidence.coreIdentity,capability.coreIdentity);
      for(const evaluator of ['independent','scheme']) {
        const coverage=report.coverage.find(l=>l.provider===evaluator);assert.ok(coverage,evaluator);
        assert.equal(coverage.calls.length,rows.length);assert.ok(coverage.calls.every(c=>c.status==='matched'));
      }
      assert.deepEqual(report.execution.calls.map(c=>c.actual),rows.map(r=>({type:'bool',value:r.expected})));
      assert.ok(!existsSync(report.execution.evidence.executable),'Library execution lease disposed');
      writeFileSync(join(artifact,id+'.json'),JSON.stringify(report,null,2)+'\n');
      lanes.push({target,mode,rows:rows.length,compilerIdentity:capability.compilerIdentity,coreIdentity:capability.coreIdentity,evidence:report.execution.evidence});
      if(target===required[0]&&mode==='debug')baseline=report;
      console.log('Installed MoonBit library '+model.id+' '+id+': '+rows.length+' original/independent/Scheme/generated rows passed');
    }
    let instrumentation;
    if(model.id==='forward') {
      const defaultLog=join(project,'.morphir/logs/frontend.ionb');
      assert.deepEqual(JSON.parse(call(['run','.','--log','--json'],0,project).stdout),compiled);
      assert.deepEqual(readFileSync(join(published,'Main.ionb')),bytes);
      assert.deepEqual([...readFileSync(defaultLog).subarray(0,4)],[224,1,0,234]);
      writeFileSync(join(artifact,'frontend.ionb'),readFileSync(defaultLog));
      const frontendLog=join(artifact,'frontend.jsonl');
      const framed=call(['run','.','--log-file',frontendLog,'--log-format','json-lines','--json-lines'],0,project).stdout.trim().split('\n').map(JSON.parse);
      assert.deepEqual(framed.filter(r=>r.type==='result').map(r=>r.data),[{successful:compiled.successful,processed:compiled.processed,publicationError:compiled.publicationError}]);
      const events=readFileSync(frontendLog,'utf8').trim().split('\n').map(JSON.parse);
      const stages=events.filter(r=>r.signal==='succeeded').map(r=>r.stage);
      assert.deepEqual(stages,['parse','profile-check','resolve','profile-check','lower','frontend']);
      assert.ok(!/\bdecide\b|\bdefault_ready\b|\bready\b|\ballowed\b|λ😀/.test(readFileSync(frontendLog,'utf8')));
      const failed=call(['run','.','--log-file',root,'--json'],0,project);
      assert.match(failed.stderr,/observability sink unavailable/);assert.deepEqual(JSON.parse(failed.stdout),compiled);
      assert.deepEqual(readFileSync(join(published,'Main.ionb')),bytes);
      const sourceStderr=call(['run','.','--log-file','@stderr','--log-format','text','--json'],0,project);
      assert.deepEqual(JSON.parse(sourceStderr.stdout),compiled);assert.match(sourceStderr.stderr,/morphir-observation-v1/);
      assert.equal(JSON.parse(call(['run','.','--frontend-profile','moonbit-model-bool-v1','--dry-run','--json'],0,project).stdout).frontends[0].defaultProfile,true);
      assert.ok(JSON.parse(call(['run','.','--frontend-provider','absent','--dry-run','--json'],2,project).stdout).error.includes('frontend.unknown_provider'));
      const target=required[0],quiet=JSON.parse(verify(target,'debug',['--telemetry-adapter','none','--json']).stdout);
      const logged=JSON.parse(verify(target,'debug',['--log-file',join(artifact,'execution.ionb'),'--json']).stdout);
      const failedSink=verify(target,'debug',['--log-file',root,'--json']);assert.match(failedSink.stderr,/observability sink unavailable/);
      for(const report of [quiet,logged,JSON.parse(failedSink.stdout)]) {
        assert.equal(report.successful,true);assert.deepEqual(report.execution.calls,baseline.execution.calls);
        for(const field of ['sourceIdentity','driverIdentity','manifestIdentity','compilerIdentity','coreIdentity'])assert.equal(report.execution.evidence[field],baseline.execution.evidence[field]);
        assert.equal(report.execution.invocationEvidence.suiteIdentity,baseline.execution.invocationEvidence.suiteIdentity);
        assert.ok(!existsSync(report.execution.evidence.executable));
      }
      const dryLog=join(artifact,'dry.ionb'),dryReceipt=join(artifact,'dry-receipt.ionb');
      const executionDry=JSON.parse(verify(target,'debug',['--dry-run','--log-file',dryLog,'--receipt',dryReceipt,'--json']).stdout);
      assert.equal(executionDry.dryRun,true);assert.equal(executionDry.calls.length,rows.length);
      assert.deepEqual(executionDry.entries,rows.map(r=>r.entry));
      assert.ok(!existsSync(dryLog));assert.ok(!existsSync(dryReceipt));
      const framedExecution=verify(target,'debug',['--json-lines']).stdout.trim().split('\n').map(JSON.parse);
      assert.equal(framedExecution.filter(r=>r.type==='result').length,1);assert.equal(framedExecution.find(r=>r.type==='result').data.successful,true);
      assert.match(verify(target,'debug').stdout,/independent decide-0: matched/);
      const mismatchCase=rows.find(r=>r.expected),bad=join(artifact,'wrong.ion');
      writeFileSync(bad,readFileSync(cases,'utf8').replace('expected:true','expected:false'));
      const mismatch=JSON.parse(verify(target,'debug',['--json'],1,bad).stdout);
      assert.equal(mismatch.successful,false);
      assert.equal(mismatch.coverage.find(l=>l.provider==='independent').calls.find(c=>c.id===mismatchCase.id).status,'mismatch');
      assert.ok(!existsSync(mismatch.execution.evidence.executable));
      writeFileSync(join(artifact,'mismatch.json'),JSON.stringify(mismatch,null,2)+'\n');
      instrumentation={frontendStages:stages,frontendNeutral:true,executionNeutral:true,failedSinkNeutral:true,dryRun:true,stdoutFraming:true,mismatchRejected:true};
    }
    visibility.push({model,original,generated:generatedSnapshot,canonical});
    models.push({id:model.id,frontend:descriptor,sourceIdentity:hash(model.source),checkpointIdentity:hash(bytes),symbolsIdentity:hash(symbols),entries:model.entries.length,private:model.private.length,rows:rows.length,lanes,originalCompilerLanes:required.length*2,rejectedEntries,rejectedSources:3,lossyJsonRejected:true,publicationPreserved:true,...(instrumentation?{instrumentation}:{})});
  }
  const privacy=testCompilerPrivacy({run,root,output,visibility,compilers,deps});
  const summary={profile:'morphir-installed-library-v1',package:pack.integrity,requiredTargets:required,models,entries:13,rowsPerLane:42,publicLibraryLanes:required.length*2*5,allPrivateSourceCompiled:true,privacy};
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed MoonBit library: '+required.join(', ')+' debug/release; 6 libraries, 13 public entries, 42 exhaustive rows passed.');
  return summary;
}

function testCompilerPrivacy({run,root,output,visibility,compilers,deps}) {
  const workspace=join(root,'library-visibility');mkdirSync(workspace);
  const sdk=deps.find(d=>d.startsWith('finos/morphir-sdk=')).slice('finos/morphir-sdk='.length);
  cpSync(sdk,join(workspace,'sdk'),{recursive:true,filter:path=>includeDependencyPath(sdk,path,excluded)});
  const members=['./sdk','./consumer'],imports=[],aliases=[],probes=[];
  for(const {model,original,generated,canonical} of visibility)for(const [kind,path] of [['original',original],['generated',generated]]) {
    const directory=kind+'-'+model.id;cpSync(path,join(workspace,directory),{recursive:true,filter:p=>includeDependencyPath(path,p,excluded)});
    members.push('./'+directory);
    const manifest=readFileSync(join(path,'moon.mod'),'utf8'),module=manifest.match(/^name\s*=\s*"([^"]+)"/m)[1];
    const version=manifest.match(/^version\s*=\s*"([^"]+)"/m)[1],alias=kind+'_'+model.id;
    imports.push(JSON.stringify(module+'@'+version));aliases.push(JSON.stringify(module)+' @'+alias);
    for(const symbol of model.private) {
      const name=symbol.original;
      if(kind==='generated')assert.match(readFileSync(join(path,'library.mbt'),'utf8'),new RegExp('^fn '+name+'\\(', 'm'),'Private source spelling remains readable');
      assert.match(name,/^[a-zA-Z_][a-zA-Z0-9_]*$/);
      probes.push({model:model.id,kind,name,source:`pub fn probe() -> Unit { ignore(@${alias}.${name}) }\n`});
    }
  }
  const consumer=join(workspace,'consumer');mkdirSync(consumer);
  writeFileSync(join(consumer,'moon.mod'),'name="acceptance/library-consumer"\nversion="0.0.0"\nimport { '+imports.join(', ')+' }\n');
  writeFileSync(join(consumer,'moon.pkg'),'import { '+aliases.join(', ')+' }\n');
  writeFileSync(join(consumer,'main.mbt'),'pub fn baseline() -> Unit {}\n');
  writeFileSync(join(workspace,'moon.work'),'members='+JSON.stringify(members)+'\n');
  const lanes=[];
  for(const [target,{compilerHome,env}] of compilers)for(const mode of ['debug','release']) {
    const checked=run(join(compilerHome,'bin/moon'),['test','--frozen','--target',target,'-p','acceptance/library-consumer',...(mode==='release'?['--release']:[])],{cwd:workspace,env});
    assert.match(checked.stdout,/Total tests: 0, passed: 0, failed: 0/);
    writeFileSync(join(output,'visibility-'+target+'-'+mode+'.log'),checked.stdout+'\n'+checked.stderr);
    lanes.push({target,mode,generatedLibraries:6,allPrivateCompiled:true});
  }
  const {compilerHome,env}=compilers.values().next().value;
  const check=()=>run(join(compilerHome,'bin/moon'),['check','--frozen','--target','js','./consumer'],{cwd:workspace,env,status:0});
  check();
  const probePath=join(consumer,'probe.mbt');
  for(const [index,probe] of probes.entries()) {
    writeFileSync(probePath,probe.source);
    const rejected=run(join(compilerHome,'bin/moon'),['check','--frozen','--target','js','./consumer'],{cwd:workspace,env,status:null});
    assert.ok((rejected.stdout+rejected.stderr).includes(probe.name),'Private compiler rejection identifies requested value');
    writeFileSync(join(output,'private-'+index+'.log'),rejected.stdout+'\n'+rejected.stderr);
  }
  rmSync(probePath);check();
  assert.equal(probes.length,16);
  return {lanes,privateAccess:probes.map(({model,kind,name})=>({model,kind,name,rejected:true})),restored:true};
}
