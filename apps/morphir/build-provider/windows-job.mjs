import {mkdtempSync,writeFileSync,readFileSync,lstatSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,extname,delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';

// Private JSON is an explicit control-plane opt-out. Model payloads stay Ion.
export function windowsJob(program,args,{cwd,env,timeout}) {
  const environment=env||process.env;
  const path=Object.entries(environment).find(([key])=>key.toLowerCase()==='path')?.[1]||'';
  const bases=/[\\/]/.test(program)?[resolve(cwd||process.cwd(),program)]:[resolve(cwd||process.cwd(),program),...path.split(delimiter).filter(Boolean).map(dir=>resolve(dir,program))];
  const names=bases.flatMap(base=>extname(base)?[base]:[base+'.exe',base+'.com']);
  const executable=names.find(name=>existsSync(name)&&lstatSync(name).isFile());
  if(!executable||!['.exe','.com'].includes(extname(executable).toLowerCase()))throw Error('execution.spawn_failed: Windows supervision requires an executable');
  const launcher=join(process.env.SystemRoot||process.env.SYSTEMROOT||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');
  if(!existsSync(launcher))throw Error('execution.tree_termination_unavailable');
  const directory=mkdtempSync(join(tmpdir(),'morphir-windows-job-'));
  const stop=join(directory,'stop'),receipt=join(directory,'receipt.json'),request=join(directory,'request.json');
  try {
    const value=JSON.stringify({profile:'morphir-windows-job-v1',program:executable,args,cwd:resolve(cwd||process.cwd()),owner:process.pid,deadline:Date.now()+timeout,stop,receipt});
    if(Buffer.byteLength(value)>131072)throw Error('execution.supervision_limit');
    writeFileSync(request,value,{flag:'wx'});
  } catch(error) {rmSync(directory,{recursive:true,force:true});throw error;}
  return {
    // PowerShell's compiler needs the OS directory and a writable temp folder
    // even when the model runner deliberately receives a minimal environment.
    env:{SystemRoot:process.env.SystemRoot||process.env.SYSTEMROOT,TEMP:process.env.TEMP,TMP:process.env.TMP,...environment},
    program:launcher,args:['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('./windows-job.ps1',import.meta.url)),request],
    stop(){writeFileSync(stop,'',{flag:'a'});},
    complete(){
      try {
        const stat=lstatSync(receipt);
        if(!stat.isFile()||stat.size>4096)throw Error();
        const value=JSON.parse(readFileSync(receipt,'utf8'));
        if(value.profile!=='morphir-windows-job-v1'||value.terminated!==true||!Number.isInteger(value.pid)||value.pid<0||!Number.isInteger(value.exitCode)||!['','execution.deadline','execution.cancelled','execution.owner_exited'].includes(value.reason))throw Error();
        rmSync(directory,{recursive:true,force:true});
        return value;
      } catch {throw Error('execution.tree_termination_failed');}
    }
  };
}
