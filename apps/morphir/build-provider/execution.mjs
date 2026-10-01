import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync,rmSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {buildLibrary} from './project.mjs';
import {hash,fileIdentity} from './identity.mjs';
import {capabilities,assertRuntime,linkedRuntime,assertLinkedRuntime} from './capabilities.mjs';
const path=resolve(process.argv[2]);
const root=dirname(path), statePath=join(root,'session.json');
function trace(value) {
  if(value===null||value===undefined||value==='')return '';
  assert.ok(typeof value==='string'&&/^00-[a-f0-9]{32}-[a-f0-9]{16}-0[01]$/.test(value),'observability.invalid_trace_context');
  assert.ok(!/^0+$/.test(value.split('-')[1])&&!/^0+$/.test(value.split('-')[2]),'observability.invalid_trace_context');return value;
}
try {
  const request=JSON.parse(readFileSync(path,'utf8'));
  assert.ok(Number.isInteger(request.timeout)&&request.timeout>0&&request.timeout<=600000);
  const traceparent=trace(request.traceparent);
  if(request.operation==='capabilities') {
    process.stdout.write(JSON.stringify(capabilities(request)));
  } else if(request.operation==='build') {
    assert.ok(!existsSync(statePath),'execution.already_built');
    const descriptor=capabilities(request).targets.find(c=>c.target===request.target&&c.compile&&c.run);
    assert.ok(descriptor,'execution.target_unavailable');
    const driver=JSON.parse(request.driver);
    const evidence=await buildLibrary(request,path,{driver,retain:true,capability:descriptor});
    evidence.driverIdentity=hash(request.driver);
    evidence.manifestIdentity=hash(request.manifest);
    evidence.runtimeIdentity=descriptor.runtime.identity;
    evidence.runtimeVersion=descriptor.runtime.version;
    if(descriptor.runtime.kind==='native-process')evidence.linkedRuntime=linkedRuntime(evidence.executable);
    if(request.toolchainPin)evidence.toolchainPin=request.toolchainPin;
    writeFileSync(statePath,JSON.stringify({evidence,nextAttempt:1}),{flag:'wx'});
    process.stdout.write(JSON.stringify(evidence));
  } else if(request.operation==='invoke') {
    const state=JSON.parse(readFileSync(statePath,'utf8')),evidence=state.evidence;
    assert.equal(request.attemptId,String(state.nextAttempt),'execution.wrong_attempt');
    assert.equal(request.leaseId,evidence.leaseId,'execution.wrong_lease');
    assert.equal(request.target,evidence.target,'execution.wrong_target');
    assertRuntime(evidence.capability);assertLinkedRuntime(evidence.linkedRuntime||[]);
    assert.equal(fileIdentity(evidence.executable),evidence.executableIdentity,'execution.changed_executable');
    const input=join(root,'suite.ionb'), output=join(root,'outcomes.ionb');
    assert.equal(fileIdentity(input),request.suiteIdentity,'execution.changed_suite');
    state.nextAttempt++;writeFileSync(statePath,JSON.stringify(state));
    rmSync(output,{force:true});
    const runtime=evidence.capability.runtime, io=[input,output,request.suiteIdentity,traceparent];
    const program=runtime.kind==='native-process'?evidence.executable:runtime.path;
    const args=runtime.kind==='native-process'?io:runtime.runner?[runtime.runner,evidence.executable,...io]:[evidence.executable,...io];
    const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout:request.timeout,killSignal:'SIGKILL',maxBuffer:1048576,env:{PATH:process.env.PATH,MORPHIR_TRACEPARENT:traceparent,MORPHIR_LEASE_ID:evidence.leaseId,MORPHIR_TARGET:evidence.target,MORPHIR_ATTEMPT_ID:request.attemptId}});
    assert.ok(!result.error,'execution.runner_failed: '+result.error?.message);
    assert.equal(result.status,0,'execution.driver_failed: '+result.stderr);
    assert.equal(result.stdout,'','execution.unexpected_stdout');
    assert.ok(existsSync(output),'execution.missing_output');
    assert.ok(readFileSync(output).length<=1048576,'execution.output_limit');
    assert.equal(fileIdentity(evidence.executable),evidence.executableIdentity,'execution.changed_executable');assertRuntime(evidence.capability);assertLinkedRuntime(evidence.linkedRuntime||[]);
    process.stdout.write(JSON.stringify({leaseId:evidence.leaseId,target:evidence.target,attemptId:request.attemptId,traceparent,suiteIdentity:request.suiteIdentity,executableIdentity:evidence.executableIdentity}));
  } else throw Error('execution.invalid_operation');
} catch(error) {process.stderr.write(error.message+'\n');process.exitCode=1;}
