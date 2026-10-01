import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {buildLibrary} from './project.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex');
const path=resolve(process.argv[2]);
const root=dirname(path), statePath=join(root,'session.json');
try {
  const request=JSON.parse(readFileSync(path,'utf8'));
  assert.ok(Number.isInteger(request.timeout)&&request.timeout>0&&request.timeout<=600000);
  if(request.operation==='build') {
    assert.ok(!existsSync(statePath),'execution.already_built');
    assert.equal(request.target,'js');
    const driver=JSON.parse(request.driver);
    const evidence=await buildLibrary(request,path,{driver,retain:true});
    evidence.driverIdentity=hash(request.driver);
    evidence.manifestIdentity=hash(request.manifest);
    evidence.runtimeIdentity=hash(readFileSync(process.execPath));
    evidence.runtimeVersion=process.version;
    writeFileSync(statePath,JSON.stringify(evidence),{flag:'wx'});
    process.stdout.write(JSON.stringify(evidence));
  } else if(request.operation==='invoke') {
    const evidence=JSON.parse(readFileSync(statePath,'utf8'));
    assert.equal(request.leaseId,evidence.leaseId,'execution.wrong_lease');
    assert.equal(hash(readFileSync(evidence.executable)),evidence.executableIdentity,'execution.changed_executable');
    assert.equal(hash(readFileSync(process.execPath)),evidence.runtimeIdentity,'execution.changed_runtime');
    const input=join(root,'suite.ionb'), output=join(root,'outcomes.ionb');
    assert.equal(hash(readFileSync(input)),request.suiteIdentity,'execution.changed_suite');
    const result=spawnSync(process.execPath,[evidence.executable,input,output,request.suiteIdentity],{cwd:root,encoding:'utf8',timeout:request.timeout,maxBuffer:1048576,env:{PATH:process.env.PATH}});
    assert.ok(!result.error,result.error?.message);
    assert.equal(result.status,0,'execution.driver_failed: '+result.stderr);
    assert.equal(result.stdout,'','execution.unexpected_stdout');
    assert.ok(readFileSync(output).length<=1048576,'execution.output_limit');
    process.stdout.write(JSON.stringify({leaseId:evidence.leaseId,suiteIdentity:request.suiteIdentity,executableIdentity:evidence.executableIdentity}));
  } else throw Error('execution.invalid_operation');
} catch(error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
