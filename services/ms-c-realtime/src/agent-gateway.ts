import { AGENT_MESSAGE_TYPES, envelope, validateEnvelope } from '../../shared/src/agent-protocol.ts';
import { authenticateAgent } from '../../shared/src/agent-auth.ts';
import { pool, one, tx } from '../../shared/src/db.ts';
import { appendEvent, listen } from '../../shared/src/events.ts';
import { config } from '../../shared/src/config.ts';
import { log } from '../../shared/src/logger.ts';
import { redactObject, redactText } from '../../shared/src/redaction.ts';

const sessions = new Map();
const redispatchAfterSeconds = 15;

function jsonSend(ws, message) {
  if (ws.readyState !== 1) return false;
  const text = JSON.stringify(message);
  if (Buffer.byteLength(text) > config.maxAgentMessageBytes) return false;
  ws.send(text);
  return true;
}

function commandType(type) {
  return ({
    executeJob: 'command.executeJob',
    refreshInventory: 'command.refreshInventory',
    collectDiagnostics: 'command.collectDiagnostics',
    updateAgent: 'command.updateAgent',
    cancel: 'command.cancel',
  })[type] || null;
}

async function claimDispatch(commandId) {
  return tx(async (client) => {
    const result = await client.query(
      `update ar_commands
       set status='dispatched',
           dispatched_at=coalesce(dispatched_at,now()),
           last_dispatch_at=now(),
           dispatch_attempts=dispatch_attempts+1,
           version=version+1
       where id=$1
         and expires_at>now()
         and (status='queued' or (status='dispatched' and coalesce(last_dispatch_at,to_timestamp(0)) < now()-make_interval(secs=>$2::int)))
       returning *`,
      [commandId, redispatchAfterSeconds],
    );
    if (!result.rowCount) return null;
    const row = result.rows[0];
    await appendEvent(client, {
      organizationId: row.organization_id,
      type: row.dispatch_attempts > 1 ? 'command.redispatched' : 'command.dispatched',
      aggregateType: 'command',
      aggregateId: row.id,
      payload: {
        commandId: row.id,
        agentId: row.agent_id,
        machineId: row.machine_id,
        type: row.type,
        attempt: row.dispatch_attempts,
      },
    });
    return row;
  });
}

export async function dispatchPending(agentId) {
  const session = sessions.get(agentId);
  if (!session?.ws || session.ws.readyState !== 1) return 0;
  const candidates = await pool.query(
    `select id from ar_commands
     where agent_id=$1 and expires_at>now()
       and (status='queued' or (status='dispatched' and coalesce(last_dispatch_at,to_timestamp(0)) < now()-make_interval(secs=>$2::int)))
     order by created_at limit 50`,
    [agentId, redispatchAfterSeconds],
  );
  let count = 0;
  for (const candidate of candidates.rows) {
    const command = await claimDispatch(candidate.id);
    if (!command) continue;
    const type = commandType(command.type);
    if (!type) {
      await pool.query(
        `update ar_commands set status='rejected',completed_at=now(),error_code='UNSUPPORTED_COMMAND_TYPE',error_summary='Tipo de comando não suportado pelo gateway.' where id=$1 and status='dispatched'`,
        [command.id],
      );
      continue;
    }
    const sent = jsonSend(session.ws, envelope(type, {
      commandId: command.id,
      jobId: command.job_id,
      type: command.type,
      payload: command.payload,
      expiresAt: command.expires_at,
      dispatchAttempt: command.dispatch_attempts,
    }, command.id));
    if (!sent) break;
    count += 1;
  }
  return count;
}

async function updateInventory(agent, msg) {
  const p = redactObject(msg.payload || {});
  await tx(async (client) => {
    const machine = p.machine || {};
    await client.query(
      `update ar_machines set display_name=coalesce($2,display_name),hostname=coalesce($3,hostname),os_name=coalesce($4,os_name),os_version=coalesce($5,os_version),architecture=coalesce($6,architecture),metadata=metadata||$7::jsonb,updated_at=now() where id=$1`,
      [agent.machine_id, machine.displayName || null, machine.hostname || null, machine.osName || null, machine.osVersion || null, machine.architecture || null, JSON.stringify(machine.metadata || {})],
    );
    const sql = p.sqlBackup || {};
    await client.query(
      `insert into ar_sqlbackup_installations(machine_id,present,install_path,app_version,cli_version,service_name,service_status,discovery_source,discovery_confidence,detected_at,raw_sanitized)
       values($1,$2,$3,$4,$5,$6,$7,$8,$9,now(),$10::jsonb)
       on conflict(machine_id) do update set present=excluded.present,install_path=excluded.install_path,app_version=excluded.app_version,cli_version=excluded.cli_version,service_name=excluded.service_name,service_status=excluded.service_status,discovery_source=excluded.discovery_source,discovery_confidence=excluded.discovery_confidence,detected_at=now(),raw_sanitized=excluded.raw_sanitized`,
      [agent.machine_id, Boolean(sql.present), sql.installPath || null, sql.appVersion || null, sql.cliVersion || null, sql.serviceName || null, sql.serviceStatus || null, sql.discoverySource || null, sql.discoveryConfidence ?? null, JSON.stringify(sql.raw || {})],
    );
    const seen = [];
    for (const job of Array.isArray(p.jobs) ? p.jobs : []) {
      const stable = String(job.stableKey || job.nativeJobId || job.name || '').trim();
      if (!stable) continue;
      seen.push(stable);
      await client.query(
        `insert into ar_jobs(machine_id,native_job_id,stable_key,name,job_type,is_scheduled,schedule_state,last_native_run_at,source,confidence,databases,destinations,active,last_seen_at,metadata)
         values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,true,now(),$13::jsonb)
         on conflict(machine_id,stable_key) do update set native_job_id=excluded.native_job_id,name=excluded.name,job_type=excluded.job_type,is_scheduled=excluded.is_scheduled,schedule_state=excluded.schedule_state,last_native_run_at=excluded.last_native_run_at,source=excluded.source,confidence=excluded.confidence,databases=excluded.databases,destinations=excluded.destinations,inventory_version=ar_jobs.inventory_version+1,active=true,last_seen_at=now(),metadata=excluded.metadata`,
        [agent.machine_id, job.nativeJobId || null, stable, String(job.name || stable).slice(0, 300), job.jobType || null, job.isScheduled ?? null, job.scheduleState || null, job.lastNativeRunAt || null, job.source || null, job.confidence ?? null, JSON.stringify(job.databases || []), JSON.stringify(job.destinations || []), JSON.stringify(job.metadata || {})],
      );
    }
    // Inventory.changed may be partial. Only a declared complete inventory is allowed
    // to deactivate jobs that disappeared from the latest snapshot.
    if (p.inventoryComplete === true) {
      if (seen.length) await client.query(`update ar_jobs set active=false where machine_id=$1 and not(stable_key=any($2::text[]))`, [agent.machine_id, seen]);
      else await client.query(`update ar_jobs set active=false where machine_id=$1`, [agent.machine_id]);
    }
    await client.query(`update ar_agents set capabilities=$2::jsonb,last_seen_at=now(),updated_at=now() where id=$1 and revoked_at is null`, [agent.id, JSON.stringify(p.capabilities || agent.capabilities || {})]);
    await appendEvent(client, {
      organizationId: agent.organization_id,
      type: 'inventory.updated', aggregateType: 'machine', aggregateId: agent.machine_id,
      payload: { machineId: agent.machine_id, agentId: agent.id, jobs: seen.length, inventoryComplete: p.inventoryComplete === true, sqlBackupPresent: Boolean(sql.present) },
    });
  });
}

function transitionFor(msg) {
  if (msg.type === 'command.accepted') return { status: 'accepted', time: 'accepted_at', event: 'command.accepted', allowed: ['queued', 'dispatched'] };
  if (msg.type === 'command.rejected') return { status: 'rejected', time: 'completed_at', event: 'command.rejected', allowed: ['queued', 'dispatched', 'accepted'] };
  if (msg.type === 'command.progress') return { status: 'running', time: 'started_at', event: 'command.running', allowed: ['dispatched', 'accepted', 'running'] };
  if (msg.type === 'command.completed') {
    const reported = String(msg.payload?.status || '').toLowerCase();
    const status = reported === 'cancelled' ? 'cancelled' : msg.payload?.success === false ? 'failed' : 'succeeded';
    return { status, time: 'completed_at', event: status === 'cancelled' ? 'command.cancelled' : status === 'failed' ? 'command.failed' : 'command.succeeded', allowed: ['queued', 'dispatched', 'accepted', 'running'] };
  }
  return null;
}

async function commandTransition(agent, msg) {
  const commandId = msg.payload?.commandId || msg.correlationId;
  if (!commandId) return;
  const transition = transitionFor(msg);
  if (!transition) return;
  const result = redactObject(msg.payload?.result || {});
  const errorSummary = redactText(String(msg.payload?.errorSummary || '')).slice(0, 2000) || null;
  await tx(async (client) => {
    const updated = await client.query(
      `update ar_commands set status=$2,${transition.time}=coalesce(${transition.time},now()),
       result=case when $3::jsonb='{}'::jsonb then result else $3::jsonb end,
       error_code=coalesce($4,error_code),error_summary=coalesce($5,error_summary),version=version+1
       where id=$1 and agent_id=$6 and status=any($7::text[]) returning *`,
      [commandId, transition.status, JSON.stringify(result), msg.payload?.errorCode || null, errorSummary, agent.id, transition.allowed],
    );
    if (!updated.rowCount) return;
    await appendEvent(client, {
      organizationId: agent.organization_id, type: transition.event, aggregateType: 'command', aggregateId: commandId,
      payload: { commandId, agentId: agent.id, machineId: agent.machine_id, status: transition.status, progress: msg.payload?.progress ?? null },
    });
  });
}

async function executionMessage(agent, msg) {
  const p = redactObject(msg.payload || {});
  const commandId = p.commandId || msg.correlationId || null;
  await tx(async (client) => {
    let executionId = p.executionId || null;
    if (msg.type === 'execution.started') {
      const result = await client.query(
        `insert into ar_executions(id,job_id,machine_id,command_id,source,backup_type,status,started_at)
         values(coalesce($1::uuid,gen_random_uuid()),$2,$3,$4,'remote',$5,'running',coalesce($6::timestamptz,now()))
         on conflict(id) do update set command_id=coalesce(ar_executions.command_id,excluded.command_id) returning id`,
        [executionId, p.jobId || null, agent.machine_id, commandId, p.backupType || null, p.startedAt || null],
      );
      executionId = result.rows[0]?.id || executionId;
    } else {
      if (!executionId && commandId) {
        const r = await client.query(`select id from ar_executions where command_id=$1 order by started_at desc limit 1`, [commandId]);
        executionId = r.rows[0]?.id || null;
      }
      const allowedStatus = new Set(['succeeded', 'failed', 'cancelled', 'unknown']);
      const status = allowedStatus.has(String(p.status)) ? String(p.status) : 'unknown';
      if (executionId) {
        await client.query(
          `update ar_executions set status=$2,completed_at=coalesce($3::timestamptz,now()),duration_seconds=$4,exit_code=$5,error_category=$6,summary=$7,cli_output=$8,raw_sanitized=$9::jsonb where id=$1`,
          [executionId, status, p.completedAt || null, p.durationSeconds ?? null, p.exitCode ?? null, p.errorCategory || null, redactText(p.summary || '').slice(0, 4000), redactText(p.cliOutput || '').slice(0, config.maxCliOutputBytes), JSON.stringify(p.raw || {})],
        );
      }
    }
    await appendEvent(client, {
      organizationId: agent.organization_id, type: msg.type, aggregateType: 'machine', aggregateId: agent.machine_id,
      payload: { machineId: agent.machine_id, agentId: agent.id, commandId, executionId, status: p.status || 'running' },
    });
  });
}

async function diagnosticMessage(agent, msg) {
  const p = redactObject(msg.payload || {});
  await tx(async (client) => {
    await client.query(
      `insert into ar_diagnostics(organization_id,machine_id,agent_id,command_id,status,summary,payload,completed_at)
       values($1,$2,$3,$4,'ready',$5::jsonb,$6::jsonb,now())`,
      [agent.organization_id, agent.machine_id, agent.id, p.commandId || msg.correlationId || null, JSON.stringify(p.summary || {}), JSON.stringify(p.payload || {})],
    );
    await appendEvent(client, { organizationId: agent.organization_id, type: 'diagnostic.ready', aggregateType: 'machine', aggregateId: agent.machine_id, payload: { machineId: agent.machine_id, agentId: agent.id, commandId: p.commandId || msg.correlationId || null } });
  });
}

export async function acceptAgentSocket(ws, request) {
  const agent = await authenticateAgent(request.headers.authorization);
  if (!agent) { ws.close(4401, 'unauthorized'); return; }
  const previous = sessions.get(agent.id);
  if (previous?.ws && previous.ws !== ws) { try { previous.ws.close(4009, 'replaced'); } catch {} }
  sessions.set(agent.id, { ws, connectedAt: Date.now() });
  await tx(async (client) => {
    await client.query(`update ar_agents set status='online',connected_at=now(),last_seen_at=now(),last_ip=$2,updated_at=now() where id=$1 and revoked_at is null`, [agent.id, request.socket.remoteAddress || null]);
    await appendEvent(client, { organizationId: agent.organization_id, type: 'agent.online', aggregateType: 'agent', aggregateId: agent.id, payload: { agentId: agent.id, machineId: agent.machine_id } });
  });
  jsonSend(ws, envelope('welcome', { agentId: agent.id, machineId: agent.machine_id, protocolVersion: 1, heartbeatIntervalSeconds: config.heartbeatIntervalSeconds, serverTime: new Date().toISOString() }));
  dispatchPending(agent.id).catch(() => {});

  ws.on('message', async (raw) => {
    try {
      if (raw.length > config.maxAgentMessageBytes) { ws.close(4409, 'message-too-large'); return; }
      const msg = JSON.parse(raw.toString('utf8'));
      const invalid = validateEnvelope(msg, AGENT_MESSAGE_TYPES);
      if (invalid) { ws.close(4400, 'bad-envelope'); return; }
      const heartbeat = await pool.query(
        `update ar_agents set last_seen_at=now(),status='online',version=coalesce($2,version),capabilities=coalesce($3::jsonb,capabilities),updated_at=now()
         where id=$1 and status not in ('revoked','blocked') and revoked_at is null returning id`,
        [agent.id, msg.type === 'hello' ? msg.payload?.version || null : null, msg.type === 'hello' ? JSON.stringify(msg.payload?.capabilities || {}) : null],
      );
      if (!heartbeat.rowCount) { ws.close(4403, 'revoked-or-blocked'); return; }
      if (msg.type === 'hello' && msg.payload?.version) {
        await pool.query(`insert into ar_agent_version_history(agent_id,version,channel) values($1,$2,$3)`, [agent.id, msg.payload.version, msg.payload.channel || agent.channel]);
      }
      if (msg.type === 'inventory.snapshot' || msg.type === 'inventory.changed') await updateInventory(agent, msg);
      else if (msg.type.startsWith('command.')) await commandTransition(agent, msg);
      else if (msg.type.startsWith('execution.')) await executionMessage(agent, msg);
      else if (msg.type === 'diagnostic.completed') await diagnosticMessage(agent, msg);
    } catch (error) {
      log('warn', 'agent_message_error', { agentId: agent.id, error: error.message });
    }
  });
  ws.on('close', async () => {
    if (sessions.get(agent.id)?.ws !== ws) return;
    sessions.delete(agent.id);
    await tx(async (client) => {
      await client.query(`update ar_agents set status='offline',disconnected_at=now(),updated_at=now() where id=$1 and status<>'revoked' and revoked_at is null`, [agent.id]);
      await appendEvent(client, { organizationId: agent.organization_id, type: 'agent.offline', aggregateType: 'agent', aggregateId: agent.id, payload: { agentId: agent.id, machineId: agent.machine_id } });
    }).catch(() => {});
  });
}


async function expireStaleCommands() {
  await tx(async (client) => {
    const expired = await client.query(
      `update ar_commands set status='expired',completed_at=now(),error_code='TTL_EXPIRED',error_summary='Comando expirou antes da execução.'
       where status in ('queued','dispatched','accepted') and expires_at<now() returning *`,
    );
    for (const row of expired.rows) {
      await appendEvent(client, { organizationId: row.organization_id, type: 'command.expired', aggregateType: 'command', aggregateId: row.id, payload: { commandId: row.id, agentId: row.agent_id, machineId: row.machine_id } });
    }
    const lost = await client.query(
      `update ar_commands set status='failed',completed_at=now(),error_code='RUNNING_TIMEOUT',error_summary='Comando permaneceu em execução além do limite operacional.'
       where status='running' and started_at < now()-make_interval(secs=>$1::int) returning *`,
      [config.commandMaxRunningSeconds],
    );
    for (const row of lost.rows) {
      await appendEvent(client, { organizationId: row.organization_id, type: 'command.failed', aggregateType: 'command', aggregateId: row.id, payload: { commandId: row.id, agentId: row.agent_id, machineId: row.machine_id, status: 'failed', errorCode: 'RUNNING_TIMEOUT' } });
    }
  });
}

export async function startCommandDispatcher(signal) {
  const commandListener = await listen('ar_command_dispatch', async (payload) => {
    const event = await one(`select payload from ar_outbox_events where id=$1`, [payload]);
    const id = event?.payload?.agentId;
    if (id) await dispatchPending(id);
  });
  const lifecycleListener = await listen('ar_domain_events', async (eventId) => {
    const event = await one(`select event_type,aggregate_id from ar_outbox_events where id=$1`, [eventId]);
    if (event?.event_type === 'agent.revoked' || event?.event_type === 'agent.blocked') {
      const session = sessions.get(event.aggregate_id);
      if (session?.ws) try { session.ws.close(4403, event.event_type); } catch {}
    }
  });
  const timer = setInterval(async () => {
    const ids = Array.from(sessions.keys());
    for (const id of ids) await dispatchPending(id).catch(() => {});
    await expireStaleCommands();
  }, 5000);
  timer.unref?.();
  signal?.addEventListener('abort', () => {
    clearInterval(timer);
    commandListener.close().catch(() => {});
    lifecycleListener.close().catch(() => {});
  }, { once: true });
}

export async function markStaleAgentsOffline() {
  const result = await pool.query(
    `update ar_agents set status='offline',disconnected_at=coalesce(disconnected_at,now()),updated_at=now()
     where status='online' and revoked_at is null and coalesce(last_seen_at,connected_at,created_at)<now()-make_interval(secs=>$1::int)
     returning id,machine_id`,
    [config.offlineAfterSeconds],
  );
  return result.rowCount;
}
