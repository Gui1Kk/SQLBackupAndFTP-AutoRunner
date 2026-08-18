import fs from 'node:fs/promises';
import path from 'node:path';

export default async function handler(_req,res){
  try{
    const data=await fs.readFile(path.join(process.cwd(),'assets/AutoRunner.png'));
    res.statusCode=200;
    res.setHeader('content-type','image/png');
    res.setHeader('cache-control','public, max-age=86400, immutable');
    res.setHeader('x-content-type-options','nosniff');
    res.end(data);
  }catch{res.statusCode=404;res.end();}
}
