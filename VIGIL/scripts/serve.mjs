#!/usr/bin/env node
/** Zero-dependency static host for the prebuilt bundle. No API, auth or remote calls. */
import { createServer } from 'node:http';
import { readFile, realpath, stat } from 'node:fs/promises';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.json':'application/json; charset=utf-8','.ico':'image/x-icon','.woff2':'font/woff2'};
export async function createBundleServer(directory=resolve(projectRoot,'dist')){
  let root;
  try{root=await realpath(directory);if(!(await stat(resolve(root,'index.html'))).isFile())throw new Error('Missing index');}
  catch{throw new Error(`Prebuilt app not found at ${directory}. Extract the full ZIP, or run npm ci and npm run build in the source project.`);}
  return createServer(async(req,res)=>{
    const reply=(status,body)=>{res.writeHead(status,{'Content-Type':'text/plain; charset=utf-8','X-Content-Type-Options':'nosniff','Cache-Control':'no-store'});res.end(req.method==='HEAD'?undefined:body);};
    if(req.method!=='GET'&&req.method!=='HEAD'){res.setHeader('Allow','GET, HEAD');reply(405,'Only GET and HEAD are supported.');return;}
    try{
      const path=decodeURIComponent(new URL(req.url??'/','http://vigil.local').pathname);
      if(path.includes('\0')||path.includes('\\')||path.split('/').includes('..')){reply(400,'Invalid file path.');return;}
      const requested=resolve(root,`.${path==='/'?'/index.html':path}`);
      if(!requested.startsWith(root+sep)){reply(404,'Not found.');return;}
      const file=await realpath(requested);
      if(!file.startsWith(root+sep)||!(await stat(file)).isFile()){reply(404,'Not found.');return;}
      const body=await readFile(file);
      res.writeHead(200,{'Content-Type':types[extname(file).toLowerCase()]??'application/octet-stream','Content-Length':body.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
      res.end(req.method==='HEAD'?undefined:body);
    }catch(error){reply(error instanceof URIError?400:404,error instanceof URIError?'Invalid encoded path.':'Not found.');}
  });
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const args=process.argv.slice(2);let port=Number(process.env.PORT??8787);
    if(args.length){if(args.length!==2||args[0]!=='--port')throw new Error('Usage: node scripts/serve.mjs [--port 8787]');port=Number(args[1]);}
    if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Choose a port from1 to65535.');
    const server=await createBundleServer();
    server.on('error',error=>{console.error(error.code==='EADDRINUSE'?`Port ${port} is already in use. Try: node scripts/serve.mjs --port ${port<65535?port+1:8787}`:error.message);process.exitCode=1;});
    server.listen(port,'0.0.0.0',()=>{console.log(`\nVIGIL — synthetic training only\nOpen http://localhost:${port}\nPrebuilt bundle · no npm install needed · Ctrl+C to stop\nProfiles/reports stay in this browser/origin. Keep JSON backups.\nListening on0.0.0.0; use a trusted local network/firewall, not a public server.\n`);});
    const close=()=>server.close(()=>process.exit(0));process.once('SIGINT',close);process.once('SIGTERM',close);
  }catch(error){console.error(error.message);process.exitCode=1;}
}
