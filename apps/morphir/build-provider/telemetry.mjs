// Host-only exporter worker. Observation payloads remain native Ion; this small
// JSON control file is an explicit control-plane projection, never model data.
import {readFileSync,lstatSync} from 'node:fs';
import {supervised} from './supervision.mjs';
try {
  const requestPath=process.argv[2];
  if(!lstatSync(requestPath).isFile()||lstatSync(requestPath).size>65536)throw Error('telemetry.request_limit');
  const request=JSON.parse(readFileSync(requestPath,'utf8'));
  if(request.profile!=='morphir-telemetry-export-v1'||typeof request.program!=='string'||!request.program||request.program.length>4096||
    !Array.isArray(request.args)||request.args.length>128||request.args.some(a=>typeof a!=='string'||a.length>4096)||
    typeof request.payload!=='string'||typeof request.cancelFile!=='string'||request.cancelFile.length>4096||
    !Number.isInteger(request.timeout)||request.timeout<1||request.timeout>5000)throw Error('telemetry.invalid_request');
  const stat=lstatSync(request.payload);
  if(!stat.isFile()||stat.size>4194304)throw Error('telemetry.payload_limit');
  const payload=readFileSync(request.payload);
  const result=await supervised(request.program,request.args,{timeout:request.timeout,cancelFile:request.cancelFile,limit:1024,input:payload});
  if(result.code!==0)throw Error('telemetry.export_failed');
  // Exporter diagnostics never become observations and never enter result stdout.
} catch {
  process.stderr.write('telemetry.export_unavailable\n');process.exitCode=1;
}
