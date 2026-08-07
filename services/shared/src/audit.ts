import { redactObject } from './redaction.ts';

export async function writeAudit(client, { organizationId=null, principal, action, resourceType=null, resourceId=null, decision='allow', request=null, summary={} }) {
  const ip = request?.ip || null;
  const ua = request?.headers?.['user-agent'] || null;
  const requestId = request?.id || null;
  await client.query(
    `insert into ar_audit_events(organization_id,actor_type,actor_id,action,resource_type,resource_id,decision,origin_ip,user_agent,request_id,summary)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
    [organizationId, principal?.actorType || 'system', principal?.actorId || 'system', action, resourceType, resourceId, decision, ip, ua, requestId, JSON.stringify(redactObject(summary))]
  );
}
