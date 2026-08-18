import fs from 'node:fs/promises';
import path from 'node:path';

const FILES=new Map([
  ['index.html',{path:'apps/central-web/index.html',type:'text/html; charset=utf-8',cache:'no-store'}],
  ['app.js',{path:'apps/central-web/app.js',type:'text/javascript; charset=utf-8',cache:'public, max-age=300'}],
  ['app.css',{path:'apps/central-web/app.css',type:'text/css; charset=utf-8',cache:'public, max-age=300'}],
]);

export default async function handler(req,res){
  const base=`https://${req.headers.host||'localhost'}`;
  const url=new URL(req.url||'/',base);
  const name=url.searchParams.get('file')||'index.html';
  const entry=FILES.get(name);
  if(!entry){res.statusCode=404;res.end('Not found');return;}
  try{
    const data=await fs.readFile(path.join(process.cwd(),entry.path));
    res.setHeader('content-type',entry.type);
    res.setHeader('cache-control',entry.cache);
    res.setHeader('x-content-type-options','nosniff');
    res.setHeader('x-frame-options','DENY');
    res.setHeader('referrer-policy','no-referrer');
    res.setHeader('content-security-policy',"default-src 'self'; connect-src 'self' wss:; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
    res.statusCode=200;res.end(data);
  }catch(error){
    res.statusCode=500;res.setHeader('content-type','application/json; charset=utf-8');
    res.end(JSON.stringify({error:'panel_asset_unavailable'}));
  }
}
