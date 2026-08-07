import { GraphQLScalarType, Kind } from 'graphql';
import { many, one } from '../../shared/src/db.ts';
import { getPrincipal, resolveOrganizationScope } from '../../shared/src/authz.ts';
import { DomainError } from '../../shared/src/problem.ts';
import { decodeCursor, encodeCursor } from '../../shared/src/pagination.ts';
import { listen } from '../../shared/src/events.ts';

export const typeDefs = /* GraphQL */ `
  scalar JSON
  scalar DateTime

  type PageInfo { hasNextPage: Boolean!, endCursor: String }
  type FleetSummary { organizations: Int!, clients: Int!, machines: Int!, agentsOnline: Int!, agentsOffline: Int!, jobs: Int!, failures24h: Int!, pendingCommands: Int! }
  type Organization { id: ID!, name: String!, slug: String!, status: String!, createdAt: DateTime! }
  type Client { id: ID!, organizationId: ID!, code: String, name: String!, status: String!, machinesTotal: Int!, jobsTotal: Int!, agentsOnline: Int!, createdAt: DateTime! }
  type Machine { id: ID!, clientId: ID!, displayName: String!, hostname: String, osName: String, osVersion: String, architecture: String, agent: Agent, sqlBackup: SqlBackupInstallation, jobs: [Job!]!, lastExecution: Execution }
  type Agent { id: ID!, status: String!, version: String!, channel: String!, protocolVersion: Int!, capabilities: JSON!, lastSeenAt: DateTime, connectedAt: DateTime, lastIp: String }
  type SqlBackupInstallation { present: Boolean!, installPath: String, appVersion: String, cliVersion: String, serviceName: String, serviceStatus: String, discoverySource: String, discoveryConfidence: Int, detectedAt: DateTime }
  type Job { id: ID!, machineId: ID!, nativeJobId: String, stableKey: String!, name: String!, jobType: String, isScheduled: Boolean, scheduleState: String, lastNativeRunAt: DateTime, source: String, confidence: Int, databases: JSON!, destinations: JSON!, active: Boolean!, lastSeenAt: DateTime! }
  type Execution { id: ID!, jobId: ID, machineId: ID!, commandId: ID, source: String!, backupType: String, status: String!, startedAt: DateTime!, completedAt: DateTime, durationSeconds: Float, exitCode: Int, errorCategory: String, summary: String, cliOutput: String }
  type Command { id: ID!, machineId: ID!, agentId: ID!, jobId: ID, type: String!, status: String!, payload: JSON!, createdAt: DateTime!, expiresAt: DateTime!, acceptedAt: DateTime, startedAt: DateTime, completedAt: DateTime, result: JSON, errorCode: String, errorSummary: String }
  type AuditEvent { id: ID!, actorType: String!, actorId: String!, action: String!, resourceType: String, resourceId: String, decision: String!, summary: JSON!, createdAt: DateTime! }
  type DomainEvent { id: ID!, organizationId: ID, eventType: String!, aggregateType: String, aggregateId: String, payload: JSON!, createdAt: DateTime! }

  type ClientEdge { cursor: String!, node: Client! }
  type ClientConnection { edges: [ClientEdge!]!, pageInfo: PageInfo! }
  type MachineEdge { cursor: String!, node: Machine! }
  type MachineConnection { edges: [MachineEdge!]!, pageInfo: PageInfo! }
  type ExecutionEdge { cursor: String!, node: Execution! }
  type ExecutionConnection { edges: [ExecutionEdge!]!, pageInfo: PageInfo! }
  type AuditEdge { cursor: String!, node: AuditEvent! }
  type AuditConnection { edges: [AuditEdge!]!, pageInfo: PageInfo! }

  type Query {
    me: JSON!
    fleetSummary(organizationId: ID): FleetSummary!
    organizations: [Organization!]!
    clients(organizationId: ID, first: Int = 50, after: String): ClientConnection!
    client(id: ID!): Client
    machines(clientId: ID, organizationId: ID, first: Int = 50, after: String): MachineConnection!
    machine(id: ID!): Machine
    job(id: ID!): Job
    executions(machineId: ID, jobId: ID, first: Int = 100, after: String): ExecutionConnection!
    command(id: ID!): Command
    audit(organizationId: ID, first: Int = 100, after: String): AuditConnection!
  }

  type Subscription {
    events(organizationId: ID, eventTypes: [String!]): DomainEvent!
  }
`;

function parseJsonLiteral(ast) {
  switch (ast.kind) {
    case Kind.STRING:
    case Kind.BOOLEAN: return ast.value;
    case Kind.INT:
    case Kind.FLOAT: return Number(ast.value);
    case Kind.NULL: return null;
    case Kind.LIST: return ast.values.map(parseJsonLiteral);
    case Kind.OBJECT: return Object.fromEntries(ast.fields.map((f) => [f.name.value, parseJsonLiteral(f.value)]));
    default: return null;
  }
}

function scalarJson() {
  return new GraphQLScalarType({
    name: 'JSON',
    serialize: (v) => v,
    parseValue: (v) => v,
    parseLiteral: parseJsonLiteral,
  });
}

const DateTime = new GraphQLScalarType({
  name: 'DateTime',
  serialize(value) { return value == null ? null : new Date(value).toISOString(); },
  parseValue(value) { const d = new Date(value); if (Number.isNaN(d.getTime())) throw new TypeError('DateTime inválido'); return d.toISOString(); },
  parseLiteral(ast) { if (ast.kind !== Kind.STRING) return null; const d = new Date(ast.value); return Number.isNaN(d.getTime()) ? null : d.toISOString(); },
});

async function principal(ctx, permission, orgId = null) {
  const p = ctx.principal || await getPrincipal({ headers: ctx.request.headers });
  if (!p) throw new DomainError('UNAUTHENTICATED', 'Autenticação obrigatória.', 401);
  // Reuse REST authorization by comparing a virtual request only when necessary.
  const { requirePrincipal } = await import('../../shared/src/authz.ts');
  return requirePrincipal({ headers: ctx.request.headers }, permission, orgId);
}

function clampFirst(value, max = 250) { return Math.max(1, Math.min(Number(value) || 50, max)); }
function timeCursor(after) {
  if (!after) return null;
  const parsed = decodeCursor(after);
  if (!parsed?.ts || !parsed?.id) throw new DomainError('CURSOR_INVALID', 'Cursor inválido.', 400);
  return parsed;
}
function connection(rows, first) {
  const hasNextPage = rows.length > first;
  const slice = rows.slice(0, first);
  const edges = slice.map((row) => ({ cursor: encodeCursor({ ts: row.created_at || row.started_at, id: row.id }), node: mapRow(row) }));
  return { edges, pageInfo: { hasNextPage, endCursor: edges.at(-1)?.cursor || null } };
}
function mapRow(r) {
  if (!r) return r;
  const out = {};
  for (const [k, v] of Object.entries(r)) {
    const camel = k.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
    out[camel] = v;
  }
  return out;
}

async function organizationForMachine(machineId) {
  return one(`select c.organization_id from ar_machines m join ar_clients c on c.id=m.client_id where m.id=$1`, [machineId]);
}
async function organizationForJob(jobId) {
  return one(`select c.organization_id from ar_jobs j join ar_machines m on m.id=j.machine_id join ar_clients c on c.id=m.client_id where j.id=$1`, [jobId]);
}

async function hydrateMachine(row) {
  if (!row) return null;
  const [agent, sqlBackup, jobs, lastExecution] = await Promise.all([
    one(`select * from ar_agents where machine_id=$1 order by created_at desc limit 1`, [row.id]),
    one(`select * from ar_sqlbackup_installations where machine_id=$1`, [row.id]),
    many(`select * from ar_jobs where machine_id=$1 and active=true order by name`, [row.id]),
    one(`select * from ar_executions where machine_id=$1 order by started_at desc limit 1`, [row.id]),
  ]);
  return { ...mapRow(row), agent: mapRow(agent), sqlBackup: mapRow(sqlBackup), jobs: jobs.map(mapRow), lastExecution: mapRow(lastExecution) };
}

export const resolvers = {
  JSON: scalarJson(),
  DateTime,
  Query: {
    me: async (_root, _args, ctx) => await principal(ctx, 'clients:read'),
    fleetSummary: async (_root, { organizationId }, ctx) => {
      const p = await principal(ctx, 'clients:read');
      const org = await resolveOrganizationScope(p, organizationId || null);
      const row = await one(`select
        (select count(*) from ar_organizations where ($1::uuid is null or id=$1))::int organizations,
        (select count(*) from ar_clients where ($1::uuid is null or organization_id=$1))::int clients,
        (select count(*) from ar_machines m join ar_clients c on c.id=m.client_id where ($1::uuid is null or c.organization_id=$1))::int machines,
        (select count(*) from ar_agents a join ar_machines m on m.id=a.machine_id join ar_clients c on c.id=m.client_id where a.status='online' and ($1::uuid is null or c.organization_id=$1))::int agents_online,
        (select count(*) from ar_agents a join ar_machines m on m.id=a.machine_id join ar_clients c on c.id=m.client_id where a.status<>'online' and ($1::uuid is null or c.organization_id=$1))::int agents_offline,
        (select count(*) from ar_jobs j join ar_machines m on m.id=j.machine_id join ar_clients c on c.id=m.client_id where j.active and ($1::uuid is null or c.organization_id=$1))::int jobs,
        (select count(*) from ar_executions e join ar_machines m on m.id=e.machine_id join ar_clients c on c.id=m.client_id where e.status='failed' and e.started_at>now()-interval '24 hours' and ($1::uuid is null or c.organization_id=$1))::int failures_24h,
        (select count(*) from ar_commands where status in ('queued','dispatched','accepted','running') and ($1::uuid is null or organization_id=$1))::int pending_commands`, [org]);
      return mapRow(row);
    },
    organizations: async (_r, _a, ctx) => { const p = await principal(ctx, 'clients:read'); if (p.role !== 'platform_owner') return (await many(`select * from ar_organizations where id=$1`, [p.organizationId])).map(mapRow); return (await many(`select * from ar_organizations order by name`)).map(mapRow); },
    clients: async (_r, { organizationId, first, after }, ctx) => {
      const p = await principal(ctx, 'clients:read'); const org = await resolveOrganizationScope(p, organizationId || null); const n = clampFirst(first); const c = timeCursor(after);
      const rows = await many(`select c.*,count(distinct m.id)::int machines_total,count(distinct j.id) filter(where j.active)::int jobs_total,count(distinct a.id) filter(where a.status='online')::int agents_online
        from ar_clients c left join ar_machines m on m.client_id=c.id left join ar_agents a on a.machine_id=m.id left join ar_jobs j on j.machine_id=m.id
        where ($1::uuid is null or c.organization_id=$1) and ($2::timestamptz is null or (c.created_at,c.id)<($2,$3::uuid)) group by c.id order by c.created_at desc,c.id desc limit $4`, [org, c?.ts || null, c?.id || null, n + 1]);
      return connection(rows, n);
    },
    client: async (_r, { id }, ctx) => { const row = await one(`select * from ar_clients where id=$1`, [id]); if (!row) return null; await principal(ctx, 'clients:read', row.organization_id); return mapRow(row); },
    machines: async (_r, { clientId, organizationId, first, after }, ctx) => {
      const p = await principal(ctx, 'machines:read'); const org = await resolveOrganizationScope(p, organizationId || null); const n = clampFirst(first); const c = timeCursor(after);
      const rows = await many(`select m.*,c.organization_id from ar_machines m join ar_clients c on c.id=m.client_id where ($1::uuid is null or c.organization_id=$1) and ($2::uuid is null or m.client_id=$2) and ($3::timestamptz is null or (m.created_at,m.id)<($3,$4::uuid)) order by m.created_at desc,m.id desc limit $5`, [org, clientId || null, c?.ts || null, c?.id || null, n + 1]);
      const hydrated = await Promise.all(rows.map(hydrateMachine));
      return connection(hydrated.map((x) => ({ ...x, created_at: x.createdAt, id: x.id })), n);
    },
    machine: async (_r, { id }, ctx) => { const row = await one(`select m.*,c.organization_id from ar_machines m join ar_clients c on c.id=m.client_id where m.id=$1`, [id]); if (!row) return null; await principal(ctx, 'machines:read', row.organization_id); return hydrateMachine(row); },
    job: async (_r, { id }, ctx) => { const row = await one(`select j.*,c.organization_id from ar_jobs j join ar_machines m on m.id=j.machine_id join ar_clients c on c.id=m.client_id where j.id=$1`, [id]); if (!row) return null; await principal(ctx, 'jobs:read', row.organization_id); return mapRow(row); },
    executions: async (_r, { machineId, jobId, first, after }, ctx) => {
      const org = machineId ? (await organizationForMachine(machineId))?.organization_id : jobId ? (await organizationForJob(jobId))?.organization_id : null;
      const p = await principal(ctx, 'executions:read', org || null); const scoped = await resolveOrganizationScope(p, org || null); const n = clampFirst(first, 500); const c = timeCursor(after);
      const rows = await many(`select e.* from ar_executions e join ar_machines m on m.id=e.machine_id join ar_clients cl on cl.id=m.client_id where ($1::uuid is null or cl.organization_id=$1) and ($2::uuid is null or e.machine_id=$2) and ($3::uuid is null or e.job_id=$3) and ($4::timestamptz is null or (e.started_at,e.id)<($4,$5::uuid)) order by e.started_at desc,e.id desc limit $6`, [scoped, machineId || null, jobId || null, c?.ts || null, c?.id || null, n + 1]);
      return connection(rows, n);
    },
    command: async (_r, { id }, ctx) => { const row = await one(`select * from ar_commands where id=$1`, [id]); if (!row) return null; await principal(ctx, 'executions:read', row.organization_id); return mapRow(row); },
    audit: async (_r, { organizationId, first, after }, ctx) => {
      const p = await principal(ctx, 'audit:read'); const org = await resolveOrganizationScope(p, organizationId || null); const n = clampFirst(first, 500); const c = timeCursor(after);
      const rows = await many(`select * from ar_audit_events where ($1::uuid is null or organization_id=$1) and ($2::timestamptz is null or (created_at,id)<($2,$3::uuid)) order by created_at desc,id desc limit $4`, [org, c?.ts || null, c?.id || null, n + 1]);
      return connection(rows, n);
    },
  },
  Subscription: {
    events: {
      subscribe: async function* (_r, { organizationId, eventTypes }, ctx) {
        const p = await principal(ctx, 'clients:read');
        const org = await resolveOrganizationScope(p, organizationId || null);
        const queue = [];
        let wake = null;
        const listener = await listen('ar_domain_events', async (notification) => {
          const event = await one(`select * from ar_outbox_events where id=$1 and ($2::uuid is null or organization_id=$2)`, [notification.payload, org]);
          if (!event || (eventTypes?.length && !eventTypes.includes(event.event_type))) return;
          queue.push(mapRow(event));
          if (wake) { const w = wake; wake = null; w(); }
        });
        try {
          while (!ctx.signal?.aborted) {
            if (!queue.length) await new Promise((resolve) => { wake = resolve; const timer = setTimeout(resolve, 25_000); timer.unref?.(); });
            while (queue.length) yield { events: queue.shift() };
          }
        } finally { await listener.close(); }
      },
      resolve: (payload) => payload.events,
    },
  },
};
