import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {supervised} from './supervision.mjs';
const root=mkdtempSync(join(tmpdir(),'morphir-supervision-'));
try {
  if(process.platform!=='win32')for(const mode of ['deadline','cancelled','normal','normal-pipes']) {
    const pidFile=join(root,mode+'.pid'),cancelFile=join(root,mode+'.cancel');
    const descendant=`require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));setInterval(()=>{},1000)`;
    const parent=`const {spawn}=require('child_process');spawn(process.execPath,['-e',${JSON.stringify(descendant)}],{stdio:${mode==='normal-pipes'?"'inherit'":"'ignore'"}});${mode.startsWith('normal')?'setTimeout(()=>process.exit(0),100)':'setInterval(()=>{},1000)'}`;
    const result=supervised(process.execPath,['-e',parent],{cwd:root,env:process.env,timeout:400,cancelFile});
    if(mode==='cancelled')setTimeout(()=>writeFileSync(cancelFile,''),150);
    if(mode.startsWith('normal'))assert.equal((await result).code,0);
    else await assert.rejects(result,new RegExp('execution.'+mode));
    assert.ok(existsSync(pidFile),'descendant actually started');
    const pid=Number(readFileSync(pidFile,'utf8'));
    assert.throws(()=>process.kill(pid,0),{code:'ESRCH'},'descendant terminated before scratch disposal');
  }
  await assert.rejects(supervised(process.execPath,['-e',"process.stdout.write('x'.repeat(100000));setInterval(()=>{},1000)"],{timeout:1000,limit:1000}),error=>error.message==='execution.diagnostic_limit');
  if(process.platform!=='win32') {
    const pidFile=join(root,'denied.pid'),kill=process.kill;
    try {
      process.kill=(pid,...args)=>{if(pid<0)throw Object.assign(Error('denied'),{code:'EPERM'});return kill.call(process,pid,...args);};
      const started=performance.now();
      await assert.rejects(supervised(process.execPath,['-e',`require('fs').writeFileSync(${JSON.stringify(pidFile)},String(process.pid));setInterval(()=>{},1000)`],{timeout:300}),error=>error.message==='execution.deadline; execution.tree_termination_failed');
      assert.ok(performance.now()-started<2000,'unconfirmed termination is bounded');
      assert.ok(existsSync(pidFile),'real process remains for host recovery');
      kill.call(process,Number(readFileSync(pidFile,'utf8')),0);
    }finally {
      process.kill=kill;
      if(existsSync(pidFile))kill.call(process,-Number(readFileSync(pidFile,'utf8')),'SIGKILL');
    }
  }
  for(let i=0;i<12;i++)assert.equal((await supervised(process.execPath,['-e',''],{timeout:1000})).code,0);
  assert.equal(process.listenerCount('SIGTERM'),0);assert.equal(process.listenerCount('SIGINT'),0);
  console.log('Process tree, cancellation, deadline, diagnostics and listener cleanup passed');
}finally{rmSync(root,{recursive:true,force:true});}
