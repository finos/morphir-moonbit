import assert from "node:assert/strict";
import {test} from "node:test";
import {execFileSync} from "node:child_process";
import {mkdtempSync,rmSync,writeFileSync,readdirSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";

test("installed npm package compiles without a CLI",()=>{
  const directory=mkdtempSync(join(tmpdir(),"morphir-embedding-package-"));
  const source=fileURLToPath(new URL("../",import.meta.url));
  const npm=args=>execFileSync(process.execPath,[process.env.npm_execpath,...args],{cwd:source,encoding:"utf8"});
  try {
    npm(["pack","--pack-destination",directory]);
    const tarball=readdirSync(directory).find(p=>p.endsWith('.tgz'));
    npm(["install","--prefix",directory,"--ignore-scripts","--offline","--no-audit","--no-fund",join(directory,tarball)]);
    writeFileSync(join(directory,"check.mjs"), `
      import {createNodeToolchain} from '@morphir/moonbit-toolchain/node';
      const tools=createNodeToolchain();
      try {
        const built=await tools.request({operation:'compile',files:[['main.mbt','pub fn answer() -> Int { 42 }']],exports:['answer']});
        const result=await tools.request({operation:'run',artifact:built.artifact,export:'answer'});
        if(result.value!==42) throw new Error('Unexpected result');
        console.log('installed embedding passed');
      } finally {tools.dispose();}
    `);
    const env={...process.env,PATH:''};
    delete env.MOON_HOME;
    assert.equal(execFileSync(process.execPath,[join(directory,"check.mjs")],{cwd:directory,env,encoding:"utf8"}).trim(),'installed embedding passed');
  } finally {rmSync(directory,{recursive:true,force:true});}
});
