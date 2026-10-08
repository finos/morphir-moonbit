import assert from 'node:assert/strict';
import {mkdirSync,writeFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {join,delimiter} from 'node:path';
import {capabilities} from '../build-provider/capabilities.mjs';
import {hash} from '../build-provider/identity.mjs';

const profile='moonbit-model-bool-library-v1';
const provider='finos/morphir-moonbit-frontend';
const hex=value=>Buffer.from(value,'utf8').toString('hex');

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
  const models=[];
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
    for(const entry of [...model.entries,...model.private])assert.ok(ion.includes('source-'+hex(entry.original)),entry.original);
    writeFileSync(join(artifact,'Main.ion'),ion);
    assert.equal(JSON.parse(call(['run','.','--backend','moonbit','--validation','source-only','--json'],0,project).stdout).successful,true);
    const generated=readFileSync(join(published,'Main/library.mbt'),'utf8');
    assert.equal((generated.match(/^pub fn /gm)||[]).length,model.entries.length);
    assert.equal((generated.match(/^fn /gm)||[]).length,model.private.length);
    writeFileSync(join(artifact,'library.mbt'),generated);
    const symbols=readFileSync(join(published,'Main/symbols.10n'));
    assert.deepEqual([...symbols.subarray(0,4)],[224,1,0,234]);writeFileSync(join(artifact,'symbols.10n'),symbols);
    const canonical=name=>'library-'+model.id+':app/main#source-'+hex(name);
    const rows=model.entries.flatMap(entry=>{
      assert.match(entry.original,/^[a-zA-Z_][a-zA-Z0-9_]*$/);
      assert.equal(entry.arguments.length,entry.expected.length);
      assert.equal(new Set(entry.arguments.map(JSON.stringify)).size,entry.arguments.length);
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
    const lanes=[];
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
      console.log('Installed MoonBit library '+model.id+' '+id+': '+rows.length+' original/independent/Scheme/generated rows passed');
    }
    models.push({id:model.id,frontend:descriptor,sourceIdentity:hash(model.source),checkpointIdentity:hash(bytes),symbolsIdentity:hash(symbols),entries:model.entries.length,private:model.private.length,rows:rows.length,lanes,originalCompilerLanes:required.length*2});
  }
  const summary={profile:'morphir-installed-library-v1',package:pack.integrity,requiredTargets:required,models,entries:13,rowsPerLane:42,publicLibraryLanes:required.length*2*5,allPrivateSourceCompiled:true};
  writeFileSync(join(output,'summary.json'),JSON.stringify(summary,null,2)+'\n');
  console.log('Installed MoonBit library: '+required.join(', ')+' debug/release; 6 libraries, 13 public entries, 42 exhaustive rows passed.');
  return summary;
}
