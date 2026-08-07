import { pool, one, many, tx } from '../../shared/src/db.ts';
import { id, normalizeSlug } from '../../shared/src/ids.ts';
import { payloadHash, randomToken, hashAgentSecret, sha256 } from '../../shared/src/crypto.ts';
import { config } from '../../shared/src/config.ts';
import { DomainError } from '../../shared/src/problem.ts';
import { appendEvent } from '../../shared/src/events.ts';
import { writeAudit } from '../../shared/src/audit.ts';
import { redactObject } from '../../shared/src/redaction.ts';

export async function organizationById(id) { return one(`select * from ar_organizations where id=$1`, [id]); }
export async function clientById(id) {
  return one(`select c.*,o.name organization_name from ar_clients c join ar_organizations o on o.id=c.organization_id where c.id=$1`, [id]);
}
export async function machineById(id) {
  return one(`select m.*,c.organization_id,c.name client_name,a.id agent_id,a.status agent_status,a.version agent_version,a.channel agent_channel,a.last_seen_at,a.capabilities,
    s.present sqlbackup_present,s.app_version sqlbackup_version,s.cli_version sqlbackup_cli_version,s.install_path sqlbackup_install_path
    from ar_machines m join ar_clients c on c.id=m.client_id
    left join lateral (select * from ar_agents aa where aa.machine_id=m.id order by aa.created_at desc limit 1) a on true
    left join ar_sqlbackup_installations s on s.machine_id=m.id where m.id=$1`, [id]);
}
export async function agentById(id) {
  return one(`select a.*,m.client_id,c.organization_id,m.display_name,m.hostname from ar_agents a join ar_machines m on m.id=a.machine_id join ar_clients c on c.id=m.client_id where a.id=$1`, [id]);
}
export async function jobById(id) {
  return one(`select j.*,m.display_name machine_name,m.client_id,c.organization_id from ar_jobs j join ar_machines m on m.id=j.machine_id join ar_clients c on c.id=m.client_id where j.id=$1 and j.active=true`, [id]);
}
export function capability(agent, name) {
  const caps = agent?.capabilities || {};
  return caps[name] === true || caps?.commands?.[name] === true;
}
export function requireCapability(agent, name) {
  if (!capability(agent, name)) throw new DomainError('CAPABILITY_NOT_SUPPORTED', `O agente não declarou a capacidade ${name}.`, 409, { capability: name });
}

export async function createOrganization({ name, slug, authOrganizationId = null, metadata = {}, principal, request }) {
  return tx(async (client) => {
    const result = await client.query(`insert into ar_organizations(auth_organization_id,name,slug,metadata) values($1,$2,$3,$4::jsonb) returning *`, [authOrganizationId, name, normalizeSlug(slug || name), JSON.stringify(redactObject(metadata))]);
    const row = result.rows[0];
    await writeAudit(client,{organizationId:row.id,principal,action:'organization.create',resourceType:'organization',resourceId:row.id,request,summary:{name:row.name}});
    await appendEvent(client,{organizationId:row.id,type:'organization.created',aggregateType:'organization',aggregateId:row.id,payload:{organizationId:row.id,name:row.name}});
    return row;
  });
}

export async function createClient({ organizationId, code = null, name, metadata = {}, principal, request }) {
  return tx(async (client) => {
    const result = await client.query(`insert into ar_clients(organization_id,code,name,metadata) values($1,$2,$3,$4::jsonb) returning *`, [organizationId, code || null, name, JSON.stringify(redactObject(metadata))]);
    const row=result.rows[0];
    await writeAudit(client,{organizationId,principal,action:'client.create',resourceType:'client',resourceId:row.id,request,summary:{name,code}});
    await appendEvent(client,{organizationId,type:'client.created',aggregateType:'client',aggregateId:row.id,payload:{clientId:row.id,name}});
    return row;
  });
}

export async function createMachine({ clientId, siteId = null, stableKey, displayName, hostname = null, metadata = {}, principal, request }) {
  const clientRow = await clientById(clientId);
  if (!clientRow) throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado.',404);
  return tx(async (client) => {
    const result=await client.query(`insert into ar_machines(client_id,site_id,stable_key,display_name,hostname,metadata) values($1,$2,$3,$4,$5,$6::jsonb)
      on conflict(client_id,stable_key) do update set display_name=excluded.display_name,hostname=coalesce(excluded.hostname,ar_machines.hostname),updated_at=now() returning *`,
      [clientId,siteId,stableKey,displayName,hostname,JSON.stringify(redactObject(metadata))]);
    const row=result.rows[0];
    await writeAudit(client,{organizationId:clientRow.organization_id,principal,action:'machine.upsert',resourceType:'machine',resourceId:row.id,request,summary:{displayName,stableKey}});
    await appendEvent(client,{organizationId:clientRow.organization_id,type:'machine.changed',aggregateType:'machine',aggregateId:row.id,payload:{machineId:row.id}});
    return row;
  });
}

export async function createEnrollment({ organizationId, clientId, siteId = null, label = null, ttlSeconds = 900, principal, request }) {
  const ttl = Math.max(60, Math.min(Number(ttlSeconds)||900, 86400));
  const token = `arenr_${randomToken(36)}`;
  const tokenHash = sha256(token);
  const row = await tx(async (client) => {
    const result = await client.query(`insert into ar_enrollment_tokens(organization_id,client_id,site_id,token_hash,label,expires_at,created_by_type,created_by_id)
      values($1,$2,$3,$4,$5,now()+make_interval(secs=>$6::int),$7,$8) returning id,organization_id,client_id,site_id,label,expires_at,created_at`,
      [organizationId,clientId,siteId,tokenHash,label,String(ttl),principal.actorType,principal.actorId]);
    const value=result.rows[0];
    await writeAudit(client,{organizationId,principal,action:'agent.enrollment.create',resourceType:'enrollment',resourceId:value.id,request,summary:{clientId,label,ttlSeconds:ttl}});
    return value;
  });
  return { ...row, token };
}

export async function enrollAgent({ token, installId, machine, agentVersion, channel='RC', protocolVersion=1, capabilities={}, sourceIp=null }) {
  const tokenHash=sha256(token);
  const agentSecret=randomToken(48);
  return tx(async (client) => {
    const tokenResult=await client.query(`select * from ar_enrollment_tokens where token_hash=$1 for update`,[tokenHash]);
    const enrollment=tokenResult.rows[0];
    if(!enrollment || enrollment.used_at || new Date(enrollment.expires_at).getTime() < Date.now()) {
      await client.query(`insert into ar_agent_enrollment_audit(install_id,source_ip,result,detail) values($1,$2,'rejected','token_invalid_or_expired')`,[installId,sourceIp]);
      throw new DomainError('ENROLLMENT_TOKEN_INVALID','Token de enrollment inválido, expirado ou já utilizado.',401);
    }
    const stableKey=String(machine?.stableKey || installId || '').trim();
    if(!stableKey) throw new DomainError('MACHINE_IDENTITY_REQUIRED','stableKey/installId obrigatório.',400);
    const displayName=String(machine?.displayName || machine?.hostname || stableKey).slice(0,200);
    let mr=await client.query(`select * from ar_machines where client_id=$1 and stable_key=$2 for update`,[enrollment.client_id,stableKey]);
    let machineRow=mr.rows[0];
    if(!machineRow){
      mr=await client.query(`insert into ar_machines(client_id,site_id,stable_key,display_name,hostname,os_name,os_version,architecture,metadata)
        values($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb) returning *`,[enrollment.client_id,enrollment.site_id,stableKey,displayName,machine?.hostname||null,machine?.osName||null,machine?.osVersion||null,machine?.architecture||null,JSON.stringify(redactObject(machine?.metadata||{}))]);
      machineRow=mr.rows[0];
    } else {
      await client.query(`update ar_machines set display_name=$2,hostname=$3,os_name=$4,os_version=$5,architecture=$6,updated_at=now() where id=$1`,[machineRow.id,displayName,machine?.hostname||machineRow.hostname,machine?.osName||machineRow.os_name,machine?.osVersion||machineRow.os_version,machine?.architecture||machineRow.architecture]);
    }
    const existing=await client.query(`select * from ar_agents where install_id=$1 and revoked_at is null for update`,[installId]);
    if(existing.rowCount) throw new DomainError('INSTALL_ALREADY_ENROLLED','Esta instalação já possui identidade ativa.',409);
    const ar=await client.query(`insert into ar_agents(machine_id,install_id,secret_hash,version,channel,protocol_version,status,capabilities,last_ip)
      values($1,$2,$3,$4,$5,$6,'offline',$7::jsonb,$8) returning *`,[machineRow.id,installId,hashAgentSecret(agentSecret),agentVersion||'unknown',channel,protocolVersion,JSON.stringify(capabilities||{}),sourceIp]);
    const agent=ar.rows[0];
    await client.query(`update ar_enrollment_tokens set used_at=now(),used_by_agent_id=$2 where id=$1`,[enrollment.id,agent.id]);
    await client.query(`insert into ar_agent_version_history(agent_id,version,channel) values($1,$2,$3)`,[agent.id,agent.version,agent.channel]);
    await client.query(`insert into ar_agent_enrollment_audit(token_id,agent_id,install_id,source_ip,result) values($1,$2,$3,$4,'accepted')`,[enrollment.id,agent.id,installId,sourceIp]);
    await appendEvent(client,{organizationId:enrollment.organization_id,type:'agent.enrolled',aggregateType:'agent',aggregateId:agent.id,payload:{agentId:agent.id,machineId:machineRow.id,version:agent.version}});
    return { agentId:agent.id,machineId:machineRow.id,secret:agentSecret,wsUrl:config.publicWsUrl,protocolVersion:agent.protocol_version,heartbeatIntervalSeconds:config.heartbeatIntervalSeconds };
  });
}

export async function createCommand({ agent, jobId=null, type, payload={}, idempotencyKey, ttlSeconds=config.commandDefaultTtlSeconds, principal, request }) {
  if (!idempotencyKey || String(idempotencyKey).length < 8) throw new DomainError('IDEMPOTENCY_KEY_REQUIRED','Idempotency-Key obrigatório (mínimo 8 caracteres).',400);
  const safePayload=redactObject(payload);
  const hash=payloadHash({type,jobId,payload:safePayload});
  const ttl=Math.max(30,Math.min(Number(ttlSeconds)||config.commandDefaultTtlSeconds,86400));
  return tx(async(client)=>{
    const existing=await client.query(`select * from ar_commands where organization_id=$1 and actor_type=$2 and actor_id=$3 and idempotency_key=$4`,[agent.organization_id,principal.actorType,principal.actorId,idempotencyKey]);
    if(existing.rowCount){
      const row=existing.rows[0];
      if(row.payload_hash!==hash) throw new DomainError('IDEMPOTENCY_CONFLICT','A mesma Idempotency-Key já foi usada com payload diferente.',409);
      return { row, existing:true };
    }
    const cr=await client.query(`insert into ar_commands(organization_id,agent_id,machine_id,job_id,type,payload,payload_hash,idempotency_key,actor_type,actor_id,expires_at)
      values($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,now()+make_interval(secs=>$11::int)) returning *`,[agent.organization_id,agent.id,agent.machine_id,jobId,type,JSON.stringify(safePayload),hash,idempotencyKey,principal.actorType,principal.actorId,String(ttl)]);
    const row=cr.rows[0];
    await writeAudit(client,{organizationId:agent.organization_id,principal,action:`command.${type}.request`,resourceType:'command',resourceId:row.id,request,summary:{machineId:agent.machine_id,agentId:agent.id,jobId,type}});
    await appendEvent(client,{organizationId:agent.organization_id,type:'command.queued',aggregateType:'command',aggregateId:row.id,payload:{commandId:row.id,agentId:agent.id,machineId:agent.machine_id,type}});
    return { row, existing:false };
  });
}

export function commandView(row) {
  return { commandId:row.id,status:row.status,type:row.type,createdAt:row.created_at,expiresAt:row.expires_at,dispatchedAt:row.dispatched_at,acceptedAt:row.accepted_at,startedAt:row.started_at,completedAt:row.completed_at,result:row.result,errorCode:row.error_code,errorSummary:row.error_summary };
}

export async function listClients(orgId=null) {
  return many(`select c.*,count(distinct m.id)::int machines_total,count(distinct j.id) filter(where j.active)::int jobs_total,
    count(distinct a.id) filter(where a.status='online')::int agents_online from ar_clients c
    left join ar_machines m on m.client_id=c.id left join ar_agents a on a.machine_id=m.id left join ar_jobs j on j.machine_id=m.id
    where ($1::uuid is null or c.organization_id=$1) group by c.id order by c.name`,[orgId]);
}
