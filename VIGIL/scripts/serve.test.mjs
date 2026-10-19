import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createBundleServer } from './serve.mjs';

let temp,root,server,url;
before(async()=>{temp=await mkdtemp(join(tmpdir(),'vigil-host-'));root=join(temp,'dist');await mkdir(join(root,'assets'),{recursive:true});await writeFile(join(root,'index.html'),'<!doctype html><title>Actual local bundle fixture</title>');await writeFile(join(root,'assets','worker.js'),'self.postMessage({type:"ready"});');await writeFile(join(temp,'outside.txt'),'outside root fixture');await symlink(join(temp,'outside.txt'),join(root,'escape.txt'));server=await createBundleServer(root);await new Promise(resolve=>server.listen(0,'0.0.0.0',resolve));url=`http://127.0.0.1:${server.address().port}`;});
after(async()=>{if(server)await new Promise(resolve=>server.close(resolve));if(temp)await rm(temp,{recursive:true,force:true});});
describe('zero-dependency local prebuilt-bundle host',()=>{
  it('serves the actual HTML body without host restrictions or external resources',async()=>{const r=await fetch(url,{headers:{Host:'8787-example.e2b.app'}});assert.equal(r.status,200);assert.match(r.headers.get('Content-Type'),/text\/html/);assert.match(await r.text(),/Actual local bundle fixture/);});
  it('uses correct Worker/module MIME type and a real JS body',async()=>{const r=await fetch(url+'/assets/worker.js');assert.equal(r.status,200);assert.match(r.headers.get('Content-Type'),/javascript/);assert.match(await r.text(),/postMessage/);});
  it('serves HEAD with matching byte length and no body',async()=>{const get=await fetch(url);const head=await fetch(url,{method:'HEAD'});assert.equal(head.status,200);assert.equal(head.headers.get('Content-Length'),get.headers.get('Content-Length'));assert.equal(await head.text(),'');});
  it('does not silently serve HTML for a missing asset',async()=>{const r=await fetch(url+'/assets/missing.js');assert.equal(r.status,404);assert.equal(await r.text(),'Not found.');});
  it('allows only safe read methods',async()=>{const r=await fetch(url,{method:'POST',body:'not writable'});assert.equal(r.status,405);assert.equal(r.headers.get('Allow'),'GET, HEAD');});
  it('rejects malformed percent encoding and encoded backslash traversal',async()=>{assert.equal((await fetch(url+'/%xx')).status,400);assert.equal((await fetch(url+'/%2e%2e%5coutside.txt')).status,400);});
  it('never serves a symlink outside the bundle root or source parent files',async()=>{assert.equal((await fetch(url+'/escape.txt')).status,404);assert.equal((await fetch(url+'/%2e%2e/outside.txt')).status,404);});
  it('returns no-store and nosniff headers without iframe/origin blocks',async()=>{const r=await fetch(url);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal(r.headers.get('X-Content-Type-Options'),'nosniff');assert.equal(r.headers.get('X-Frame-Options'),null);});
  it('fails clearly when the prebuilt app is missing instead of pretending to run',async()=>{await assert.rejects(()=>createBundleServer(join(temp,'missing')),/Prebuilt app not found.*Extract the full ZIP/);});
});
