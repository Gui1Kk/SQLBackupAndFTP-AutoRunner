import { verifyCompactToken } from '../../shared/src/crypto.ts';
import { listen } from '../../shared/src/events.ts';
import { one } from '../../shared/src/db.ts';
import { config } from '../../shared/src/config.ts';

function protocolToken(request){
  const raw=String(request.headers['sec-websocket-protocol']||'');
  for(const item of raw.split(',').map((x)=>x.trim()))if(item.startsWith('token.'))return item.slice(6);
  return null;
}
export async function acceptUiSocket(ws,request,url){
  const token=protocolToken(request);
  const claims=verifyCompactToken(token,config.realtimeSigningSecret);
  if(!claims||claims.kind!=='ui'){ws.close(4401,'unauthorized');return;}
  const org=claims.organizationId||null;
  ws.send(JSON.stringify({type:'welcome',payload:{actorId:claims.actorId,organizationId:org,serverTime:new Date().toISOString()}}));
  const listener=await listen('ar_domain_events',async(eventId)=>{const event=await one(`select * from ar_outbox_events where id=$1 and ($2::uuid is null or organization_id=$2)`,[eventId,org]);if(event&&ws.readyState===1)ws.send(JSON.stringify({type:'event',payload:event}));});
  ws.on('close',()=>listener.close().catch(()=>{}));
}
