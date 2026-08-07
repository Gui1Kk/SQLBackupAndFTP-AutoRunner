import crypto from 'node:crypto';
import http from 'node:http';
import https from 'node:https';
import { pool, tx } from '../../shared/src/db.ts';
import { decryptSecret } from '../../shared/src/crypto.ts';
import { resolveWebhookTarget } from '../../shared/src/ssrf.ts';
import { config } from '../../shared/src/config.ts';
import { log } from '../../shared/src/logger.ts';
import { redactText } from '../../shared/src/redaction.ts';

function delayForAttempt(attempt) {
  const base = Math.min(300_000, 2_000 * (2 ** Math.max(0, attempt - 1)));
  return Math.floor(base * (0.8 + Math.random() * 0.4));
}

async function postPinnedWebhook(target,body,headers){
  const {url,address,family}=target;
  const transport=url.protocol==='https:'?https:http;
  return new Promise((resolve,reject)=>{
    const options={
      protocol:url.protocol,hostname:url.hostname,port:url.port||undefined,path:url.pathname+url.search,
      method:'POST',headers:{...headers,'content-length':Buffer.byteLength(body)},servername:url.protocol==='https:'?url.hostname:undefined,
      maxHeaderSize:16*1024,
      lookup(_hostname,_options,callback){callback(null,address,family);},
    };
    const req=transport.request(options,(res)=>{
      const chunks=[];let bytes=0;
      res.on('data',(chunk)=>{if(bytes<2048){const remaining=2048-bytes;chunks.push(chunk.subarray(0,remaining));bytes+=Math.min(chunk.length,remaining);}});
      res.on('end',()=>resolve({status:res.statusCode||0,ok:(res.statusCode||0)>=200&&(res.statusCode||0)<300,text:()=>Promise.resolve(Buffer.concat(chunks).toString('utf8'))}));
    });
    req.setTimeout(config.webhookTimeoutMs,()=>req.destroy(new Error('Timeout do webhook.')));
    req.on('error',reject);req.end(body);
  });
}

export async function materializeWebhookDeliveries(limit = 250) {
  return tx(async (client) => {
    const events = await client.query(`select e.* from ar_outbox_events e where not exists(select 1 from ar_event_inbox i where i.consumer='webhook-materializer' and i.event_id=e.id) order by e.created_at,e.id limit $1 for update skip locked`, [limit]);
    for (const event of events.rows) {
      const endpoints = await client.query(`select id,event_types from ar_webhook_endpoints where organization_id=$1 and enabled=true`, [event.organization_id]);
      for (const endpoint of endpoints.rows) {
        if (endpoint.event_types?.length && !endpoint.event_types.includes(event.event_type)) continue;
        await client.query(`insert into ar_webhook_deliveries(endpoint_id,event_id,event_type,payload) values($1,$2,$3,$4::jsonb) on conflict(endpoint_id,event_id) do nothing`, [endpoint.id,event.id,event.event_type,JSON.stringify(event.payload)]);
      }
      await client.query(`insert into ar_event_inbox(consumer,event_id) values('webhook-materializer',$1) on conflict do nothing`, [event.id]);
    }
    return events.rowCount;
  });
}

async function claimDelivery() {
  return tx(async (client) => {
    const result = await client.query(`select d.*,e.organization_id,w.url,w.secret_encrypted,w.enabled from ar_webhook_deliveries d join ar_webhook_endpoints w on w.id=d.endpoint_id join ar_outbox_events e on e.id=d.event_id where d.status in ('pending','failed') and d.next_attempt_at<=now() and w.enabled=true order by d.next_attempt_at,d.created_at limit 1 for update of d skip locked`);
    if (!result.rowCount) return null;
    const row=result.rows[0];
    await client.query(`update ar_webhook_deliveries set status='delivering',attempt_count=attempt_count+1,last_attempt_at=now() where id=$1`,[row.id]);
    return {...row,attempt_count:Number(row.attempt_count)+1};
  });
}

export async function deliverOneWebhook() {
  const d = await claimDelivery();
  if (!d) return false;
  try {
    const target = await resolveWebhookTarget(d.url);
    const secret = decryptSecret(d.secret_encrypted);
    const body = JSON.stringify({ id:d.event_id, type:d.event_type, occurredAt:new Date().toISOString(), organizationId:d.organization_id, data:d.payload });
    const timestamp = Math.floor(Date.now()/1000).toString();
    const signature = crypto.createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
    const response = await postPinnedWebhook(target,body,{'content-type':'application/json','user-agent':'AutoRunner-ControlPlane/3.0.0-RC','x-autorunner-event-id':d.event_id,'x-autorunner-event-type':d.event_type,'x-autorunner-timestamp':timestamp,'x-autorunner-signature':`v1=${signature}`});
    const excerpt = redactText((await response.text()).slice(0,2048));
    if (response.ok) {
      await pool.query(`update ar_webhook_deliveries set status='succeeded',completed_at=now(),response_status=$2,response_excerpt=$3,error_summary=null where id=$1`,[d.id,response.status,excerpt]);
    } else throw Object.assign(new Error(`HTTP ${response.status}`),{status:response.status,excerpt});
  } catch (error) {
    const dead = d.attempt_count >= config.webhookMaxAttempts;
    const delay = delayForAttempt(d.attempt_count);
    await pool.query(`update ar_webhook_deliveries set status=$2,next_attempt_at=now()+make_interval(secs=>$3::int),response_status=$4,response_excerpt=$5,error_summary=$6,completed_at=case when $2='dead_letter' then now() else null end where id=$1`,[d.id,dead?'dead_letter':'failed',Math.ceil(delay/1000),error.status||null,error.excerpt||null,redactText(String(error.message||error)).slice(0,1000)]);
    log(dead?'error':'warn','webhook_delivery_failed',{deliveryId:d.id,attempt:d.attempt_count,deadLetter:dead,error:String(error.message||error)});
  }
  return true;
}


export async function cleanupRetainedOperationalData(limit = 5000) {
  const days = Math.max(1, config.eventRetentionDays);
  return tx(async (client) => {
    const candidates = await client.query(
      `select e.id
         from ar_outbox_events e
        where e.created_at < now()-make_interval(days=>$1::int)
          and exists(select 1 from ar_event_inbox i where i.consumer='webhook-materializer' and i.event_id=e.id)
          and not exists(
            select 1 from ar_webhook_deliveries d
             where d.event_id=e.id and d.status not in ('succeeded','dead_letter')
          )
        order by e.created_at,e.id
        limit $2
        for update skip locked`,
      [days, limit]
    );
    const ids = candidates.rows.map((row) => row.id);
    if (ids.length) {
      await client.query(`delete from ar_webhook_deliveries where event_id=any($1::uuid[])`, [ids]);
      await client.query(`delete from ar_event_inbox where event_id=any($1::uuid[])`, [ids]);
      await client.query(`delete from ar_outbox_events where id=any($1::uuid[])`, [ids]);
    }
    const diagnostics = await client.query(
      `delete from ar_diagnostics where expires_at<now() and status in ('ready','failed','expired') returning id`
    );
    return { events: ids.length, diagnostics: diagnostics.rowCount };
  });
}

export function startWebhookWorkers(signal) {
  const timers=[];
  const materializer=setInterval(()=>materializeWebhookDeliveries().catch((e)=>log('error','webhook_materialize_failed',{error:e.message})),1500); materializer.unref?.();timers.push(materializer);
  const delivery=setInterval(async()=>{try{for(let i=0;i<10;i++){if(!(await deliverOneWebhook()))break;}}catch(e){log('error','webhook_worker_failed',{error:e.message});}},500); delivery.unref?.();timers.push(delivery);
  const cleanup=async()=>{try{const removed=await cleanupRetainedOperationalData();if(removed.events||removed.diagnostics)log('info','retention_cleanup',{...removed,eventRetentionDays:config.eventRetentionDays});}catch(e){log('error','retention_cleanup_failed',{error:e.message});}};
  const cleanupTimer=setInterval(cleanup,Math.max(300,config.retentionCleanupIntervalSeconds)*1000); cleanupTimer.unref?.();timers.push(cleanupTimer);
  const startupCleanup=setTimeout(cleanup,15_000); startupCleanup.unref?.();timers.push(startupCleanup);
  signal?.addEventListener('abort',()=>timers.forEach(clearInterval),{once:true});
  return ()=>timers.forEach(clearInterval);
}
