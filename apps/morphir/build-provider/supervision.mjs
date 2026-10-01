import {spawn} from 'node:child_process';
import {existsSync} from 'node:fs';

// One owned process group per command. Never resolve on `error` before `close`:
// AbortSignal's early rejection otherwise allows disposal while children run.
export async function supervised(program,args,{cwd,env,timeout,cancelFile='',limit=1048576}={}) {
  if(!Number.isInteger(timeout)||timeout<1||timeout>600000||!Number.isInteger(limit)||limit<1||limit>1048576)throw Error('execution.supervision_limit');
  if(cancelFile && existsSync(cancelFile))throw Error('execution.cancelled');
  const child=spawn(program,args,{cwd,env,detached:process.platform!=='win32',stdio:['ignore','pipe','pipe'],windowsHide:true});
  let reason='',spawnError=null,size=0,termination=null;const out=[],err=[];
  function killTree() {
    if(!child.pid)return;
    if(process.platform==='win32') {
      // taskkill is a platform capability, not an optional direct-child fallback.
      if(termination)return;
      termination=new Promise(resolve=>{
        const killer=spawn('taskkill',['/pid',String(child.pid),'/T','/F'],{stdio:'ignore',windowsHide:true});
        const timer=setTimeout(()=>{reason ||= 'execution.tree_termination_failed';killer.kill('SIGKILL');resolve();},1000);
        killer.on('error',()=>{reason ||= 'execution.tree_termination_unavailable';});
        killer.once('close',code=>{clearTimeout(timer);if(code!==0)reason ||= 'execution.tree_termination_failed';resolve();});
      });
    } else {
      try {process.kill(-child.pid,'SIGKILL');}catch(e){if(e.code!=='ESRCH')reason ||= 'execution.tree_termination_failed';}
    }
  }
  const stop=code=>{reason ||= code;killTree();};
  const signal=()=>stop('execution.cancelled');
  process.on('SIGTERM',signal);process.on('SIGINT',signal);
  const timer=setTimeout(()=>stop('execution.deadline'),timeout);
  const poll=cancelFile?setInterval(()=>{if(existsSync(cancelFile))stop('execution.cancelled');},10):null;
  const collect=(destination,data)=>{size+=data.length;if(size>limit){stop('execution.diagnostic_limit');return;}destination.push(data);};
  child.stdout.on('data',data=>collect(out,data));child.stderr.on('data',data=>collect(err,data));
  child.on('error',error=>{spawnError=error;});
  try {
    const [code,signal]=await new Promise(resolve=>child.once('close',(...result)=>resolve(result)));
    // A command may exit while a descendant is still alive with closed pipes.
    // Reclaim the group on successful exit too, before returning its evidence.
    if(process.platform!=='win32')killTree();
    if(termination)await termination;
    if(reason)throw Error(reason);
    if(spawnError)throw Error('execution.spawn_failed: '+spawnError.message);
    return {code,signal,stdout:Buffer.concat(out).toString('utf8'),stderr:Buffer.concat(err).toString('utf8')};
  } finally {
    clearTimeout(timer);if(poll)clearInterval(poll);
    process.removeListener('SIGTERM',signal);process.removeListener('SIGINT',signal);
  }
}
