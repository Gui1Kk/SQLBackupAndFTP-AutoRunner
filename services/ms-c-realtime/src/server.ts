import http from 'node:http';
import { WebSocketServer } from 'ws';
import { config } from '../../shared/src/config.ts';
import { databaseReady, pool } from '../../shared/src/db.ts';
import { log } from '../../shared/src/logger.ts';
import { acceptAgentSocket, markStaleAgentsOffline, startCommandDispatcher } from './agent-gateway.ts';
import { acceptUiSocket } from './ui-gateway.ts';

process.env.SERVICE_NAME='ms-c-realtime';
const abort=new AbortController();
const upgradeWindows=new Map();
function requestIp(req){const forwarded=String(req.headers['x-forwarded-for']||'').split(',')[0].trim();return forwarded||req.socket.remoteAddress||'unknown';}
function allowUpgrade(ip){const now=Date.now();const current=upgradeWindows.get(ip);if(!current||now-current.startedAt>=60_000){upgradeWindows.set(ip,{startedAt:now,count:1});return true;}current.count+=1;return current.count<=config.websocketUpgradesPerMinute;}
const upgradeGc=setInterval(()=>{const cutoff=Date.now()-120_000;for(const [key,value] of upgradeWindows)if(value.startedAt<cutoff)upgradeWindows.delete(key);},60_000);upgradeGc.unref?.();
const server=http.createServer(async(req,res)=>{if(req.url==='/health/live'){res.writeHead(200,{'content-type':'application/json'});return res.end('{"status":"ok","service":"ms-c"}');}if(req.url==='/health/ready'){const ok=await databaseReady();res.writeHead(ok?200:503,{'content-type':'application/json'});return res.end(JSON.stringify({status:ok?'ready':'not-ready'}));}res.writeHead(404);res.end();});
const wss=new WebSocketServer({
  noServer:true,
  maxPayload:config.maxAgentMessageBytes,
  perMessageDeflate:false,
  handleProtocols(protocols){return protocols.has('autorunner-ui')?'autorunner-ui':false;},
});
function originAllowed(origin){if(!origin)return false;try{return config.trustedOrigins.includes(new URL(origin).origin);}catch{return false;}}
server.on('upgrade',(req,socket,head)=>{
  if(!allowUpgrade(requestIp(req))){socket.write('HTTP/1.1 429 Too Many Requests\r\nRetry-After: 60\r\nConnection: close\r\n\r\n');socket.destroy();return;}
  let url;try{url=new URL(req.url||'/',`http://${req.headers.host||'localhost'}`);}catch{socket.destroy();return;}
  if(!['/ws/agent','/ws/ui'].includes(url.pathname)){socket.destroy();return;}
  if(url.pathname==='/ws/ui'&&!originAllowed(req.headers.origin)){socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');socket.destroy();return;}
  wss.handleUpgrade(req,socket,head,(ws)=>{ws.isAlive=true;ws.on('pong',()=>ws.isAlive=true);if(url.pathname==='/ws/agent')acceptAgentSocket(ws,req).catch(()=>ws.close(1011,'internal'));else acceptUiSocket(ws,req,url).catch(()=>ws.close(1011,'internal'));});
});
const ping=setInterval(()=>{for(const ws of wss.clients){if(ws.isAlive===false){ws.terminate();continue;}ws.isAlive=false;ws.ping();}},30000);ping.unref?.();
const stale=setInterval(()=>markStaleAgentsOffline().catch(()=>{}),30000);stale.unref?.();
await startCommandDispatcher(abort.signal);
server.listen(config.msCPort,config.serviceHost,()=>log('info','ms_c_listening',{port:config.msCPort}));
async function shutdown(signal){log('info','shutdown',{signal});abort.abort();clearInterval(ping);clearInterval(stale);clearInterval(upgradeGc);for(const ws of wss.clients)try{ws.close(1001,'shutdown');}catch{}await new Promise((resolve)=>server.close(resolve));await pool.end();process.exit(0);}for(const sig of ['SIGTERM','SIGINT'])process.on(sig,()=>shutdown(sig));
