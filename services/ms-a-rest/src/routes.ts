import { requirePrincipal, resolveOrganizationScope } from '../../shared/src/authz.ts';
import { pool, one, many, tx } from '../../shared/src/db.ts';
import { DomainError } from '../../shared/src/problem.ts';
import { config } from '../../shared/src/config.ts';
import { encryptSecret, randomToken, signCompactToken } from '../../shared/src/crypto.ts';
import { validateWebhookUrl } from '../../shared/src/ssrf.ts';
import { auth } from './auth.ts';
import { fromNodeHeaders } from 'better-auth/node';
import { writeAudit } from '../../shared/src/audit.ts';
import { appendEvent } from '../../shared/src/events.ts';
import {
  organizationById, clientById, machineById, agentById, jobById, requireCapability,
  createOrganization, createClient, createMachine, createEnrollment, enrollAgent,
  createCommand, commandView, listClients
} from './domain.ts';

const UUID={type:'string',format:'uuid'};
function idempotency(request){return String(request.headers['idempotency-key']||'').trim();}
function accepted(reply,row,existing=false){return reply.code(existing?200:202).send({...commandView(row),idempotentReplay:existing});}

export async function registerRoutes(app) {
  app.get('/health/live',{config:{public:true}},async()=>({status:'ok',service:'ms-a-rest',version:'3.0.0-RC'}));
  app.get('/health/ready',{config:{public:true}},async(_req,reply)=>{try{await pool.query('select 1');return {status:'ready'};}catch(e){return reply.code(503).send({status:'not_ready',reason:e.message});}});
  app.get('/api/v1/version',{config:{public:true}},async()=>({product:'SQLBackupAndFTP AutoRunner Control Plane',version:'3.0.0-RC',apiVersion:'v1'}));

  app.post('/api/v1/agent/enroll',{config:{public:true,rateLimit:{max:20,timeWindow:'1 minute'}},schema:{body:{type:'object',required:['token','installId','machine'],properties:{token:{type:'string',minLength:20},installId:{type:'string',minLength:8,maxLength:200},agentVersion:{type:'string',maxLength:50},channel:{type:'string',maxLength:20},protocolVersion:{type:'integer'},machine:{type:'object'},capabilities:{type:'object'}}}}},async(req,reply)=>{
    const result=await enrollAgent({...req.body,sourceIp:req.ip});
    return reply.code(201).send(result);
  });

  app.get('/api/v1/me',async(req)=>({principal:await requirePrincipal(req,'clients:read')}));

  app.get('/api/v1/organizations',async(req)=>{const p=await requirePrincipal(req,'clients:read');if(p.role!=='platform_owner')return many(`select * from ar_organizations where id=$1`,[p.organizationId]);return many(`select * from ar_organizations order by name`);});
  app.post('/api/v1/organizations',{schema:{body:{type:'object',required:['name'],properties:{name:{type:'string',minLength:2,maxLength:200},slug:{type:'string',maxLength:100},metadata:{type:'object'}}}}},async(req,reply)=>{
    const p=await requirePrincipal(req,'clients:manage');
    if(p.role!=='platform_owner'||!p.userId)throw new DomainError('FORBIDDEN_SCOPE','Somente platform_owner autenticado por sessão cria organizações.',403);
    const slug=String(req.body.slug||req.body.name).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'').slice(0,80);
    let authOrg=null;
    try{authOrg=await auth.api.createOrganization({body:{name:req.body.name,slug,userId:p.userId,keepCurrentActiveOrganization:false}});}catch(error){throw new DomainError('AUTH_ORGANIZATION_CREATE_FAILED','Não foi possível criar a organização no provedor de identidade.',409,{cause:error.message});}
    try{return reply.code(201).send(await createOrganization({...req.body,slug,authOrganizationId:authOrg.id,principal:p,request:req}));}
    catch(error){try{await auth.api.deleteOrganization({body:{organizationId:authOrg.id},headers:fromNodeHeaders(req.headers)});}catch{}throw error;}
  });

  app.get('/api/v1/clients',async(req)=>{const p=await requirePrincipal(req,'clients:read');const org=await resolveOrganizationScope(p,req.query?.organizationId||null);return {items:await listClients(org)};});
  app.post('/api/v1/clients',{schema:{body:{type:'object',required:['organizationId','name'],properties:{organizationId:UUID,code:{anyOf:[{type:'string',maxLength:100},{type:'null'}]},name:{type:'string',minLength:2,maxLength:200},metadata:{type:'object'}}}}},async(req,reply)=>{const p=await requirePrincipal(req,'clients:manage',req.body.organizationId);return reply.code(201).send(await createClient({...req.body,principal:p,request:req}));});
  app.get('/api/v1/clients/:clientId',async(req)=>{const row=await clientById(req.params.clientId);if(!row)throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado.',404);await requirePrincipal(req,'clients:read',row.organization_id);return row;});
  app.patch('/api/v1/clients/:clientId',async(req)=>{const row=await clientById(req.params.clientId);if(!row)throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado.',404);const p=await requirePrincipal(req,'clients:manage',row.organization_id);const next=await tx(async(c)=>{const r=await c.query(`update ar_clients set name=coalesce($2,name),code=coalesce($3,code),status=coalesce($4,status),updated_at=now() where id=$1 returning *`,[row.id,req.body?.name||null,req.body?.code||null,req.body?.status||null]);await writeAudit(c,{organizationId:row.organization_id,principal:p,action:'client.update',resourceType:'client',resourceId:row.id,request:req,summary:req.body||{}});return r.rows[0];});return next;});
  app.get('/api/v1/clients/:clientId/machines',async(req)=>{const client=await clientById(req.params.clientId);if(!client)throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado.',404);await requirePrincipal(req,'machines:read',client.organization_id);return {items:await many(`select m.*,a.id agent_id,a.status agent_status,a.version agent_version,a.last_seen_at from ar_machines m left join lateral(select * from ar_agents x where x.machine_id=m.id order by created_at desc limit 1)a on true where m.client_id=$1 order by m.display_name`,[client.id])};});
  app.post('/api/v1/clients/:clientId/machines',async(req,reply)=>{const client=await clientById(req.params.clientId);if(!client)throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado.',404);const p=await requirePrincipal(req,'machines:manage',client.organization_id);return reply.code(201).send(await createMachine({clientId:client.id,...req.body,principal:p,request:req}));});

  app.get('/api/v1/machines/:machineId',async(req)=>{const row=await machineById(req.params.machineId);if(!row)throw new DomainError('MACHINE_NOT_FOUND','Máquina não encontrada.',404);await requirePrincipal(req,'machines:read',row.organization_id);return row;});
  app.get('/api/v1/machines/:machineId/capabilities',async(req)=>{const row=await machineById(req.params.machineId);if(!row)throw new DomainError('MACHINE_NOT_FOUND','Máquina não encontrada.',404);await requirePrincipal(req,'machines:read',row.organization_id);return {machineId:row.id,agentId:row.agent_id,capabilities:row.capabilities||{},observedAt:row.last_seen_at};});
  app.get('/api/v1/machines/:machineId/jobs',async(req)=>{const row=await machineById(req.params.machineId);if(!row)throw new DomainError('MACHINE_NOT_FOUND','Máquina não encontrada.',404);await requirePrincipal(req,'jobs:read',row.organization_id);return {items:await many(`select * from ar_jobs where machine_id=$1 and active=true order by name`,[row.id])};});
  app.get('/api/v1/machines/:machineId/executions',async(req)=>{const row=await machineById(req.params.machineId);if(!row)throw new DomainError('MACHINE_NOT_FOUND','Máquina não encontrada.',404);await requirePrincipal(req,'executions:read',row.organization_id);return {items:await many(`select * from ar_executions where machine_id=$1 order by started_at desc limit 200`,[row.id])};});

  app.post('/api/v1/agents/enrollments',async(req,reply)=>{const p=await requirePrincipal(req,'agents:enroll');const org=await resolveOrganizationScope(p,req.body?.organizationId||null);if(!org)throw new DomainError('ORGANIZATION_REQUIRED','organizationId obrigatório.',400);const client=await clientById(req.body.clientId);if(!client||client.organization_id!==org)throw new DomainError('CLIENT_NOT_FOUND','Cliente não encontrado no escopo.',404);return reply.code(201).send(await createEnrollment({organizationId:org,clientId:client.id,siteId:req.body?.siteId,label:req.body?.label,ttlSeconds:req.body?.ttlSeconds,principal:p,request:req}));});
  app.post('/api/v1/agents/:agentId/revoke',async(req)=>{const agent=await agentById(req.params.agentId);if(!agent)throw new DomainError('AGENT_NOT_FOUND','Agente não encontrado.',404);const p=await requirePrincipal(req,'agents:revoke',agent.organization_id);return tx(async(c)=>{const r=await c.query(`update ar_agents set status='revoked',revoked_at=now(),updated_at=now() where id=$1 returning id,status,revoked_at`,[agent.id]);await c.query(`update ar_commands set status='cancelled',completed_at=now(),error_code='AGENT_REVOKED',error_summary='Agente revogado antes da conclusão.' where agent_id=$1 and status in ('queued','dispatched','accepted')`,[agent.id]);await writeAudit(c,{organizationId:agent.organization_id,principal:p,action:'agent.revoke',resourceType:'agent',resourceId:agent.id,request:req});await appendEvent(c,{organizationId:agent.organization_id,type:'agent.revoked',aggregateType:'agent',aggregateId:agent.id,payload:{agentId:agent.id}});return r.rows[0];});});

  for(const [path,type,permission,cap] of [
    ['inventory-refresh','refreshInventory','jobs:read','inventoryRefresh'],
    ['diagnostics','collectDiagnostics','diagnostics:request','diagnostics'],
    ['updates','updateAgent','agents:update','agentUpdate']
  ]) app.post(`/api/v1/agents/:agentId/${path}`,async(req,reply)=>{const agent=await agentById(req.params.agentId);if(!agent)throw new DomainError('AGENT_NOT_FOUND','Agente não encontrado.',404);const p=await requirePrincipal(req,permission,agent.organization_id);if(cap)requireCapability(agent,cap);const result=await createCommand({agent,type,payload:req.body||{},idempotencyKey:idempotency(req),principal:p,request:req});return accepted(reply,result.row,result.existing);});

  app.get('/api/v1/jobs/:jobId',async(req)=>{const job=await jobById(req.params.jobId);if(!job)throw new DomainError('JOB_NOT_FOUND','Job não encontrado.',404);await requirePrincipal(req,'jobs:read',job.organization_id);return job;});
  app.post('/api/v1/jobs/:jobId/executions',async(req,reply)=>{const job=await jobById(req.params.jobId);if(!job)throw new DomainError('JOB_NOT_FOUND','Job não encontrado.',404);const p=await requirePrincipal(req,'jobs:execute',job.organization_id);const agent=await one(`select a.*,c.organization_id from ar_agents a join ar_machines m on m.id=a.machine_id join ar_clients c on c.id=m.client_id where a.machine_id=$1 and a.status<>'revoked' order by a.created_at desc limit 1`,[job.machine_id]);if(!agent)throw new DomainError('AGENT_NOT_FOUND','Máquina sem agente ativo.',409);requireCapability(agent,'jobRun');const backupType=req.body?.backupType||'Default';const allowed=['Default','Full','FullCopy','Diff','TranLog','TranLogCopy'];if(!allowed.includes(backupType))throw new DomainError('BACKUP_TYPE_INVALID','Tipo de backup inválido.',400);const result=await createCommand({agent,jobId:job.id,type:'executeJob',payload:{jobId:job.id,nativeJobId:job.native_job_id,jobName:job.name,backupType},idempotencyKey:idempotency(req),principal:p,request:req});return accepted(reply,result.row,result.existing);});
  for(const [method,permission,cap] of [['post','jobs:create','jobCreate'],['patch','jobs:update','jobUpdate'],['delete','jobs:delete','jobDelete']]) app[method](method==='post'?'/api/v1/jobs':'/api/v1/jobs/:jobId',async(req)=>{const machineId=req.body?.machineId;const job=req.params?.jobId?await jobById(req.params.jobId):null;const machine=job?await machineById(job.machine_id):await machineById(machineId);if(!machine)throw new DomainError('MACHINE_NOT_FOUND','Máquina não encontrada.',404);await requirePrincipal(req,permission,machine.organization_id);const agent=await agentById(machine.agent_id);if(!agent)throw new DomainError('AGENT_NOT_FOUND','Agente não encontrado.',409);requireCapability(agent,cap);throw new DomainError('CAPABILITY_NOT_IMPLEMENTED','Contrato reservado; o fornecedor não expõe mecanismo suportado para esta mutação nesta RC.',501);});

  app.get('/api/v1/commands/:commandId',async(req)=>{const row=await one(`select * from ar_commands where id=$1`,[req.params.commandId]);if(!row)throw new DomainError('COMMAND_NOT_FOUND','Comando não encontrado.',404);await requirePrincipal(req,'executions:read',row.organization_id);return commandView(row);});
  app.post('/api/v1/commands/:commandId/cancel',async(req,reply)=>{const row=await one(`select * from ar_commands where id=$1`,[req.params.commandId]);if(!row)throw new DomainError('COMMAND_NOT_FOUND','Comando não encontrado.',404);const p=await requirePrincipal(req,'executions:cancel',row.organization_id);const agent=await agentById(row.agent_id);requireCapability(agent,'commandCancel');const result=await createCommand({agent,type:'cancel',payload:{targetCommandId:row.id},idempotencyKey:idempotency(req),principal:p,request:req});return accepted(reply,result.row,result.existing);});
  app.get('/api/v1/executions/:executionId',async(req)=>{const row=await one(`select e.*,c.organization_id from ar_executions e join ar_machines m on m.id=e.machine_id join ar_clients c on c.id=m.client_id where e.id=$1`,[req.params.executionId]);if(!row)throw new DomainError('EXECUTION_NOT_FOUND','Execução não encontrada.',404);await requirePrincipal(req,'executions:read',row.organization_id);return row;});

  app.get('/api/v1/webhooks',async(req)=>{const p=await requirePrincipal(req,'webhooks:read');const org=await resolveOrganizationScope(p,req.query?.organizationId||null);return {items:await many(`select id,organization_id,name,url,event_types,enabled,created_at,updated_at from ar_webhook_endpoints where ($1::uuid is null or organization_id=$1) order by name`,[org])};});
  app.post('/api/v1/webhooks',async(req,reply)=>{const p=await requirePrincipal(req,'webhooks:manage',req.body.organizationId);await validateWebhookUrl(req.body.url);const secret=randomToken(32);const row=await tx(async(c)=>{const r=await c.query(`insert into ar_webhook_endpoints(organization_id,name,url,event_types,secret_encrypted) values($1,$2,$3,$4,$5) returning id,organization_id,name,url,event_types,enabled,created_at`,[req.body.organizationId,req.body.name,req.body.url,req.body.eventTypes||[],encryptSecret(secret)]);await writeAudit(c,{organizationId:req.body.organizationId,principal:p,action:'webhook.create',resourceType:'webhook',resourceId:r.rows[0].id,request:req,summary:{url:req.body.url,eventTypes:req.body.eventTypes||[]}});return r.rows[0];});return reply.code(201).send({...row,secret});});
  app.delete('/api/v1/webhooks/:id',async(req,reply)=>{const row=await one(`select * from ar_webhook_endpoints where id=$1`,[req.params.id]);if(!row)throw new DomainError('WEBHOOK_NOT_FOUND','Webhook não encontrado.',404);const p=await requirePrincipal(req,'webhooks:manage',row.organization_id);await tx(async(c)=>{await c.query(`delete from ar_webhook_endpoints where id=$1`,[row.id]);await writeAudit(c,{organizationId:row.organization_id,principal:p,action:'webhook.delete',resourceType:'webhook',resourceId:row.id,request:req});});return reply.code(204).send();});

  app.get('/api/v1/integrations/api-keys',async(req)=>{
    const p=await requirePrincipal(req,'integrations:manage');
    if(p.authMethod!=='session')throw new DomainError('SESSION_REQUIRED','Gerenciamento de credenciais exige sessão de usuário.',403);
    const orgId=await resolveOrganizationScope(p,req.query?.organizationId||null);
    if(!orgId)throw new DomainError('ORGANIZATION_REQUIRED','organizationId obrigatório para listar credenciais.',400);
    const org=await organizationById(orgId);
    if(!org?.auth_organization_id)throw new DomainError('AUTH_ORGANIZATION_NOT_LINKED','Organização sem vínculo com o provedor de identidade.',409);
    const result=await auth.api.listApiKeys({query:{configId:'integration',organizationId:org.auth_organization_id,limit:100,offset:0},headers:fromNodeHeaders(req.headers)});
    return {items:(result?.apiKeys||[]).map((key)=>({id:key.id,name:key.name,prefix:key.prefix,start:key.start,enabled:key.enabled,permissions:key.permissions,metadata:key.metadata,createdAt:key.createdAt,expiresAt:key.expiresAt,lastRequest:key.lastRequest})),total:result?.total||0};
  });
  app.post('/api/v1/integrations/api-keys',async(req,reply)=>{
    const p=await requirePrincipal(req,'integrations:manage',req.body?.organizationId||null);
    if(p.authMethod!=='session'||!p.userId)throw new DomainError('SESSION_REQUIRED','Criação de credenciais exige sessão de usuário.',403);
    const orgId=await resolveOrganizationScope(p,req.body?.organizationId||null);
    if(!orgId)throw new DomainError('ORGANIZATION_REQUIRED','organizationId obrigatório.',400);
    const org=await organizationById(orgId);
    if(!org?.auth_organization_id)throw new DomainError('AUTH_ORGANIZATION_NOT_LINKED','Organização sem vínculo com o provedor de identidade.',409);
    const permissions=req.body?.permissions||{clients:['read'],machines:['read'],jobs:['read'],executions:['read']};
    const keyBody={configId:'integration',name:String(req.body?.name||'Integração').slice(0,100),organizationId:org.auth_organization_id,userId:p.userId,prefix:'ar_',metadata:{organizationId:orgId,purpose:String(req.body?.purpose||'integration').slice(0,100)},permissions};if(Number(req.body?.expiresIn)>0)keyBody.expiresIn=Number(req.body.expiresIn);const result=await auth.api.createApiKey({body:keyBody});
    await tx(async(c)=>writeAudit(c,{organizationId:orgId,principal:p,action:'integration.api_key.create',resourceType:'api_key',resourceId:result.id,request:req,summary:{name:result.name,permissions}}));
    return reply.code(201).send({id:result.id,name:result.name,key:result.key,prefix:result.prefix,start:result.start,permissions:result.permissions,createdAt:result.createdAt,expiresAt:result.expiresAt});
  });
  app.delete('/api/v1/integrations/api-keys/:id',async(req,reply)=>{
    const p=await requirePrincipal(req,'integrations:manage');
    if(p.authMethod!=='session')throw new DomainError('SESSION_REQUIRED','Revogação de credenciais exige sessão de usuário.',403);
    const orgId=await resolveOrganizationScope(p,req.query?.organizationId||null);
    if(!orgId)throw new DomainError('ORGANIZATION_REQUIRED','organizationId obrigatório para revogar credenciais.',400);
    const org=await organizationById(orgId);
    if(!org?.auth_organization_id)throw new DomainError('AUTH_ORGANIZATION_NOT_LINKED','Organização sem vínculo com o provedor de identidade.',409);
    const listed=await auth.api.listApiKeys({query:{configId:'integration',organizationId:org.auth_organization_id,limit:100,offset:0},headers:fromNodeHeaders(req.headers)});
    if(!(listed?.apiKeys||[]).some((key)=>key.id===req.params.id))throw new DomainError('API_KEY_NOT_FOUND','Credencial não encontrada no escopo.',404);
    await auth.api.deleteApiKey({body:{configId:'integration',keyId:req.params.id},headers:fromNodeHeaders(req.headers)});
    await tx(async(c)=>writeAudit(c,{organizationId:orgId,principal:p,action:'integration.api_key.delete',resourceType:'api_key',resourceId:req.params.id,request:req}));
    return reply.code(204).send();
  });

  app.post('/api/v1/realtime/token',async(req)=>{const p=await requirePrincipal(req,'clients:read');return {token:signCompactToken({kind:'ui',actorId:p.actorId,organizationId:p.organizationId,role:p.role},config.realtimeSigningSecret,120),expiresIn:120,url:config.publicWsUrl.replace(/\/ws\/agent$/,'/ws/ui')};});
}
