import { pool, tx } from './db.ts';
import { id } from './ids.ts';
import { redactObject } from './redaction.ts';

export async function appendEvent(client, { organizationId = null, type, aggregateType = null, aggregateId = null, payload = {}, eventId = id() }) {
  const sanitized = redactObject(payload);
  await client.query(
    `insert into ar_outbox_events(id,organization_id,event_type,aggregate_type,aggregate_id,payload)
     values($1,$2,$3,$4,$5,$6::jsonb) on conflict(id) do nothing`,
    [eventId, organizationId, type, aggregateType, aggregateId, JSON.stringify(sanitized)]
  );
  await client.query(`select pg_notify('ar_domain_events',$1)`, [eventId]);
  if (type.startsWith('command.')) await client.query(`select pg_notify('ar_command_dispatch',$1)`, [eventId]);
  return eventId;
}

export async function publishEvent(event) {
  return tx(async (client) => appendEvent(client, event));
}

export async function listen(channel, onNotification) {
  if (!/^[a-z_][a-z0-9_]*$/i.test(channel)) throw new Error('Canal PostgreSQL inválido.');
  const client = await pool.connect();
  await client.query(`LISTEN ${channel}`);
  const handler = (msg) => { if (msg.channel === channel) onNotification(msg.payload).catch?.(() => {}); };
  client.on('notification', handler);
  client.on('error', () => {});
  const close = async () => {
    client.removeListener('notification', handler);
    try { await client.query(`UNLISTEN ${channel}`); } catch {}
    client.release();
  };
  return { close };
}

export async function readPendingEvents(consumer, limit = 100) {
  const result = await pool.query(
    `select e.* from ar_outbox_events e
     left join ar_event_inbox i on i.consumer=$1 and i.event_id=e.id
     where i.event_id is null
     order by e.created_at,e.id limit $2`, [consumer, limit]
  );
  return result.rows;
}

export async function markEventProcessed(consumer, eventId, client = pool) {
  await client.query(`insert into ar_event_inbox(consumer,event_id) values($1,$2) on conflict do nothing`, [consumer,eventId]);
}
