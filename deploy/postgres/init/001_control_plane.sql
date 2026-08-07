BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS ar_schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_organization_id text UNIQUE,
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','archived')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  code text,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code)
);

CREATE TABLE IF NOT EXISTS ar_sites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES ar_clients(id) ON DELETE CASCADE,
  name text NOT NULL,
  timezone text NOT NULL DEFAULT 'America/Porto_Velho',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_machines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES ar_clients(id) ON DELETE CASCADE,
  site_id uuid REFERENCES ar_sites(id) ON DELETE SET NULL,
  stable_key text NOT NULL,
  display_name text NOT NULL,
  hostname text,
  os_name text,
  os_version text,
  architecture text,
  tags jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (client_id, stable_key)
);

CREATE TABLE IF NOT EXISTS ar_agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id uuid NOT NULL REFERENCES ar_machines(id) ON DELETE CASCADE,
  install_id text NOT NULL,
  secret_hash text NOT NULL,
  version text NOT NULL,
  channel text NOT NULL DEFAULT 'RC',
  protocol_version integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'offline' CHECK (status IN ('online','offline','degraded','blocked','revoked')),
  capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  connected_at timestamptz,
  disconnected_at timestamptz,
  revoked_at timestamptz,
  last_ip inet,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE ar_agents DROP CONSTRAINT IF EXISTS ar_agents_install_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ar_agents_active_install_id ON ar_agents(install_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ar_agents_machine ON ar_agents(machine_id);
CREATE INDEX IF NOT EXISTS idx_ar_agents_status_seen ON ar_agents(status, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS ar_agent_version_history (
  id bigserial PRIMARY KEY,
  agent_id uuid NOT NULL REFERENCES ar_agents(id) ON DELETE CASCADE,
  version text NOT NULL,
  channel text NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (agent_id, version, channel, observed_at)
);

CREATE TABLE IF NOT EXISTS ar_sqlbackup_installations (
  machine_id uuid PRIMARY KEY REFERENCES ar_machines(id) ON DELETE CASCADE,
  present boolean NOT NULL DEFAULT false,
  install_path text,
  app_version text,
  cli_version text,
  service_name text,
  service_status text,
  discovery_source text,
  discovery_confidence integer,
  detected_at timestamptz NOT NULL DEFAULT now(),
  raw_sanitized jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS ar_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id uuid NOT NULL REFERENCES ar_machines(id) ON DELETE CASCADE,
  native_job_id text,
  stable_key text NOT NULL,
  name text NOT NULL,
  job_type text,
  is_scheduled boolean,
  schedule_state text,
  last_native_run_at timestamptz,
  source text,
  confidence integer,
  databases jsonb NOT NULL DEFAULT '[]'::jsonb,
  destinations jsonb NOT NULL DEFAULT '[]'::jsonb,
  inventory_version bigint NOT NULL DEFAULT 1,
  active boolean NOT NULL DEFAULT true,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (machine_id, stable_key)
);
CREATE INDEX IF NOT EXISTS idx_ar_jobs_machine_active ON ar_jobs(machine_id, active);

CREATE TABLE IF NOT EXISTS ar_commands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  agent_id uuid NOT NULL REFERENCES ar_agents(id) ON DELETE CASCADE,
  machine_id uuid NOT NULL REFERENCES ar_machines(id) ON DELETE CASCADE,
  job_id uuid REFERENCES ar_jobs(id) ON DELETE SET NULL,
  type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload_hash text NOT NULL,
  idempotency_key text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','dispatched','accepted','running','succeeded','failed','cancelled','expired','rejected')),
  actor_type text NOT NULL,
  actor_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  dispatched_at timestamptz,
  last_dispatch_at timestamptz,
  dispatch_attempts integer NOT NULL DEFAULT 0,
  accepted_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  result jsonb,
  error_code text,
  error_summary text,
  version integer NOT NULL DEFAULT 1,
  UNIQUE (organization_id, actor_type, actor_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_ar_commands_agent_status ON ar_commands(agent_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_ar_commands_expiry ON ar_commands(status, expires_at);

CREATE TABLE IF NOT EXISTS ar_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid REFERENCES ar_jobs(id) ON DELETE SET NULL,
  machine_id uuid NOT NULL REFERENCES ar_machines(id) ON DELETE CASCADE,
  command_id uuid REFERENCES ar_commands(id) ON DELETE SET NULL,
  source text NOT NULL CHECK (source IN ('remote','autorunner_boot','native','manual_observed')),
  backup_type text,
  status text NOT NULL DEFAULT 'running' CHECK (status IN ('queued','running','succeeded','failed','cancelled','unknown')),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  duration_seconds numeric(14,3),
  exit_code integer,
  error_category text,
  summary text,
  cli_output text,
  raw_sanitized jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_ar_executions_machine_time ON ar_executions(machine_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_ar_executions_job_time ON ar_executions(job_id, started_at DESC);

CREATE TABLE IF NOT EXISTS ar_enrollment_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES ar_clients(id) ON DELETE CASCADE,
  site_id uuid REFERENCES ar_sites(id) ON DELETE SET NULL,
  token_hash text NOT NULL UNIQUE,
  label text,
  expires_at timestamptz NOT NULL,
  created_by_type text NOT NULL,
  created_by_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  used_at timestamptz,
  used_by_agent_id uuid REFERENCES ar_agents(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_ar_enrollment_expiry ON ar_enrollment_tokens(expires_at) WHERE used_at IS NULL;

CREATE TABLE IF NOT EXISTS ar_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  organization_id uuid REFERENCES ar_organizations(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('platform_owner','support_admin','support_operator','viewer','auditor')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, organization_id, role)
);

CREATE TABLE IF NOT EXISTS ar_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES ar_organizations(id) ON DELETE SET NULL,
  actor_type text NOT NULL,
  actor_id text NOT NULL,
  action text NOT NULL,
  resource_type text,
  resource_id text,
  decision text NOT NULL DEFAULT 'allow',
  origin_ip inet,
  user_agent text,
  request_id text,
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ar_audit_org_time ON ar_audit_events(organization_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ar_webhook_endpoints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  url text NOT NULL,
  event_types text[] NOT NULL DEFAULT ARRAY[]::text[],
  secret_encrypted text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id uuid NOT NULL REFERENCES ar_webhook_endpoints(id) ON DELETE CASCADE,
  event_id uuid NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','delivering','succeeded','failed','dead_letter')),
  attempt_count integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_attempt_at timestamptz,
  response_status integer,
  response_excerpt text,
  error_summary text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (endpoint_id, event_id)
);
CREATE INDEX IF NOT EXISTS idx_ar_webhook_pending ON ar_webhook_deliveries(status, next_attempt_at);

CREATE TABLE IF NOT EXISTS ar_event_inbox (
  consumer text NOT NULL,
  event_id uuid NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (consumer, event_id)
);

CREATE TABLE IF NOT EXISTS ar_read_machine_summary (
  machine_id uuid PRIMARY KEY REFERENCES ar_machines(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES ar_clients(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  hostname text,
  agent_id uuid,
  agent_status text,
  agent_version text,
  last_seen_at timestamptz,
  sqlbackup_present boolean,
  sqlbackup_version text,
  jobs_total integer NOT NULL DEFAULT 0,
  last_execution_status text,
  last_execution_at timestamptz,
  failures_24h integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ar_read_machine_org_client ON ar_read_machine_summary(organization_id, client_id, agent_status);


CREATE TABLE IF NOT EXISTS ar_outbox_events (
  id uuid PRIMARY KEY,
  organization_id uuid REFERENCES ar_organizations(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  aggregate_type text,
  aggregate_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ar_outbox_time ON ar_outbox_events(created_at,id);
CREATE INDEX IF NOT EXISTS idx_ar_outbox_org_time ON ar_outbox_events(organization_id,created_at DESC);

CREATE TABLE IF NOT EXISTS ar_diagnostics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES ar_organizations(id) ON DELETE CASCADE,
  machine_id uuid NOT NULL REFERENCES ar_machines(id) ON DELETE CASCADE,
  agent_id uuid REFERENCES ar_agents(id) ON DELETE SET NULL,
  command_id uuid REFERENCES ar_commands(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','collecting','ready','failed','expired')),
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (now()+interval '30 days')
);
CREATE INDEX IF NOT EXISTS idx_ar_diagnostics_machine_time ON ar_diagnostics(machine_id,created_at DESC);

CREATE TABLE IF NOT EXISTS ar_agent_enrollment_audit (
  id bigserial PRIMARY KEY,
  token_id uuid REFERENCES ar_enrollment_tokens(id) ON DELETE SET NULL,
  agent_id uuid REFERENCES ar_agents(id) ON DELETE SET NULL,
  install_id text,
  source_ip inet,
  result text NOT NULL,
  detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO ar_schema_migrations(version) VALUES ('001_control_plane') ON CONFLICT DO NOTHING;
COMMIT;
