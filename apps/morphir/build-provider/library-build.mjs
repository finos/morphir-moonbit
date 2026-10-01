import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,readdirSync,cpSync,lstatSync,realpathSync,readlinkSync,rmSync,existsSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {isWithin,includeDependencyPath} from './paths.mjs';

const requestPath=resolve(process.argv[2]);
const request=JSON.parse(readFileSync(requestPath,'utf8'));
const workspace=join(dirname(requestPath),'workspace');
const compilerVersion='0.10.14+7d59c7ec9';
const semanticPin='bc99af69a8b24d391311fae3822a87eafef3c334';
const excluded=new Set(['.git','node_modules','.mooncakes','_build']);
const deadline=Date.now()+request.timeout;
const abort=new AbortController();
process.on('SIGTERM',()=>abort.abort());
process.on('SIGINT',()=>abort.abort());
const check=()=>{assert.ok(!abort.signal.aborted,'build.cancelled');assert.ok(Date.now()<deadline,'build.deadline');};
const hash=value=>createHash('sha256').update(value).digest('hex');
function tree(root,{core=false}={}) {
  const entries=[];root=realpathSync(root);
  function walk(relative) {
    check();
    for(const entry of readdirSync(join(root,relative),{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0)) {
      if(excluded.has(entry.name)&& !(core&&entry.name==='_build'))continue;
      const path=relative?relative+'/'+entry.name:entry.name;
      const absolute=join(root,path);
      if(entry.isDirectory())walk(path);
      else if(entry.isFile())entries.push([path,'file',hash(readFileSync(absolute))]);
      else if(entry.isSymbolicLink()&&core) {
        const target=realpathSync(absolute);assert.ok(isWithin(root,target),'Core link escapes installation');
        assert.ok(lstatSync(target).isFile(),'Core links must identify files');
        entries.push([path,'link',readlinkSync(absolute),hash(readFileSync(target))]);
      } else throw Error('Unsupported dependency entry: '+path);
    }
  }
  walk('');return hash(JSON.stringify(entries));
}
async function execute(program,args,cwd,home) {
  check();const env={...process.env,MOON_HOME:home};
  delete env.MOON_WORK;
  const child=spawn(program,args,{cwd,env,stdio:['ignore','pipe','pipe'],windowsHide:true,signal:abort.signal});
  let output='',error='',size=0,overflow=false;
  const collect=(kind,data)=>{size+=data.length;if(size>1048576){overflow=true;child.kill();return;}if(kind==='out')output+=data;else error+=data;};
  child.stdout.on('data',data=>collect('out',data));child.stderr.on('data',data=>collect('err',data));
  const timer=setTimeout(()=>{abort.abort();},Math.max(1,deadline-Date.now()));
  try {
    const code=await new Promise((done,fail)=>{child.on('error',fail);child.on('close',done);});
    assert.ok(!overflow,'build.output_limit');check();
    assert.equal(code,0,`${program} ${args.join(' ')} failed: ${error}${output}`);
    return output;
  } finally {clearTimeout(timer);}
}
function manifest(root,kind='moon.mod') {
  const text=readFileSync(join(root,kind),'utf8');
  const field=name=>{const m=text.match(new RegExp('^\\s*'+name+'\\s*=\\s*"([^"]+)"','m'));assert.ok(m,'Missing '+name);return m[1];};
  return {name:field('name'),version:field('version')};
}
function safePath(path) {
  assert.ok(typeof path==='string'&&path&& !path.includes('\\') && !path.includes(':') && !path.includes('\0'));
  assert.ok(path.split('/').every(p=>p&&p!=='.'&&p!=='..'),'Invalid member path');
}
try {
  assert.equal(request.contract,'moonbit-library-v1');assert.ok(['native','js','wasm','wasm-gc'].includes(request.target));
  assert.ok(Number.isInteger(request.timeout)&&request.timeout>=1&&request.timeout<=600000);
  assert.equal(hash(request.snapshot),request.sourceIdentity,'Source identity differs');
  const home=realpathSync(request.compilerHome);
  const moon=join(home,'bin',process.platform==='win32'?'moon.exe':'moon');
  const moonc=join(home,'bin',process.platform==='win32'?'moonc.exe':'moonc');
  assert.match(await execute(moonc,['-v'],dirname(requestPath),home),/^v0\.10\.14\+7d59c7ec9 /);
  assert.equal(manifest(join(home,'lib/core')).version,compilerVersion,'Matching core version required');
  const compilerIdentity=hash(Buffer.concat([readFileSync(moonc),readFileSync(moon)]));
  const coreIdentity=tree(join(home,'lib/core'),{core:true});
  mkdirSync(workspace);const project=join(workspace,'generated');mkdirSync(project);
  const snapshot=JSON.parse(request.snapshot);const seen=new Set();
  for(const [path,[encoding,content]] of snapshot) {
    safePath(path);assert.ok(!seen.has(path.toLowerCase()),'Duplicate source member');seen.add(path.toLowerCase());
    assert.ok(encoding==='text'||encoding==='binary');
    mkdirSync(dirname(join(project,path)),{recursive:true});
    if(encoding==='binary')assert.ok(Array.isArray(content)&&content.every(b=>Number.isInteger(b)&&b>=0&&b<=255));
    writeFileSync(join(project,path),encoding==='text'?content:Buffer.from(content));
  }
  assert.equal(manifest(project).name,request.projectId,'Generated manifest identity differs');
  const identities=[];const roots=[];
  for(const [i,dependency] of request.dependencies.entries()) {
    assert.equal(dependency.moduleName,'finos/morphir-sdk','Unaudited dependency contract');
    assert.equal(dependency.version,'0.1.0');assert.equal(dependency.semanticPin,semanticPin);
    assert.equal(dependency.apiProfile,'morphir-sdk-concrete-v1');
    const supplied=request.suppliedDependencies[dependency.moduleName];assert.ok(supplied,'build.unresolved_dependency');
    const root=realpathSync(supplied);const info=manifest(root);
    assert.equal(info.name,dependency.moduleName);assert.equal(info.version,dependency.version);
    assert.equal(JSON.parse(readFileSync(join(root,'conformance/bindings.json'),'utf8')).pin,dependency.semanticPin);
    const sourceIdentity=tree(root);const copied=join(workspace,'dependency'+i);
    cpSync(root,copied,{recursive:true,filter:path=>includeDependencyPath(root,path,excluded)});
    assert.equal(tree(copied),sourceIdentity,'Dependency copy differs');
    roots.push({supplied:root,copied,sourceIdentity});
    identities.push({...dependency,sourceIdentity});
  }
  // A frozen workspace supplies every module. No update/install/setup operation is used.
  writeFileSync(join(workspace,'moon.work'),'members='+JSON.stringify(['./generated',...roots.map((_,i)=>'./dependency'+i)])+'\n');
  const frozenSource=tree(project);
  assert.ok(!existsSync(join(project,'_build')),'Stale build outputs');
  const compilerOutput=join(workspace,'compiler-output');
  assert.ok(!existsSync(compilerOutput),'Stale compiler output directory');
  await execute(moon,['build','--frozen','--target',request.target,'--target-dir',compilerOutput],workspace,home);
  const interfaces=[];
  function outputFiles(root,relative='') {
    for(const entry of readdirSync(join(root,relative),{withFileTypes:true})) {
      const path=relative?relative+'/'+entry.name:entry.name;
      if(entry.isDirectory())outputFiles(root,path);
      else if(entry.isFile()&&entry.name.endsWith('.mi'))interfaces.push(path);
    }
  }
  assert.ok(existsSync(compilerOutput),'No fresh compiler output');outputFiles(compilerOutput);
  const packageTail=request.projectId.split('/').at(-1);
  assert.ok(interfaces.some(path=>path===request.target+'/debug/build/'+packageTail+'.mi'||path.endsWith('/'+request.projectId+'/'+packageTail+'.mi')),'No fresh generated library interface: '+interfaces.join(', '));
  const buildIdentity=tree(compilerOutput);
  assert.equal(tree(project),frozenSource,'Generated source changed during build');
  assert.equal(hash(Buffer.concat([readFileSync(moonc),readFileSync(moon)])),compilerIdentity,'Compiler changed during build');
  assert.equal(tree(join(home,'lib/core'),{core:true}),coreIdentity,'Core source changed during build');
  for(const dep of roots) {assert.equal(tree(dep.copied),dep.sourceIdentity,'Copied dependency changed');assert.equal(tree(dep.supplied),dep.sourceIdentity,'Supplied dependency changed');}
  check();
  const evidence={successful:true,frozen:true,leaseId:request.leaseId,projectId:request.projectId,contract:request.contract,sourceIdentity:request.sourceIdentity,target:request.target,compilerVersion,compilerIdentity,coreIdentity,buildIdentity,dependencies:identities};
  rmSync(workspace,{recursive:true,force:true});
  process.stdout.write(JSON.stringify(evidence));
} catch(error) {const message=abort.signal.aborted?(Date.now()>=deadline?'build.deadline':'build.cancelled'):error.message;process.stderr.write(message+'\n');process.exitCode=1;}
finally {rmSync(workspace,{recursive:true,force:true});}
