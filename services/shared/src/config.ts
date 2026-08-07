import process from 'node:process';

export function env(name, fallback = undefined) {
  const value = process.env[name];
  return value === undefined || value === '' ? fallback : value;
}
export function requiredEnv(name) {
  const value = env(name);
  if (!value) throw new Error(`Variável obrigatória ausente: ${name}`);
  return value;
}
export function envInt(name, fallback) {
  const raw = env(name);
  if (raw === undefined) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) throw new Error(`Variável ${name} deve ser inteira.`);
  return parsed;
}
export function envBool(name, fallback = false) {
  const raw = env(name);
  if (raw === undefined) return fallback;
  return ['1','true','yes','on','sim'].includes(String(raw).toLowerCase());
}
export function csvEnv(name, fallback = []) {
  const raw = env(name);
  return raw ? raw.split(',').map((x) => x.trim()).filter(Boolean) : fallback;
}
export const config = Object.freeze({
  nodeEnv: env('NODE_ENV', 'production'),
  databaseUrl: requiredEnv('DATABASE_URL'),
  betterAuthUrl: env('BETTER_AUTH_URL', 'http://localhost:8080'),
  betterAuthSecret: requiredEnv('BETTER_AUTH_SECRET'),
  trustedOrigins: csvEnv('TRUSTED_ORIGINS', ['http://localhost:8080']),
  allowPublicSignup: envBool('ALLOW_PUBLIC_SIGNUP', false),
  agentSecretPepper: requiredEnv('AGENT_SECRET_PEPPER'),
  realtimeSigningSecret: requiredEnv('REALTIME_SIGNING_SECRET'),
  internalServiceSecret: requiredEnv('INTERNAL_SERVICE_SECRET'),
  webhookEncryptionKey: requiredEnv('WEBHOOK_ENCRYPTION_KEY'),
  publicBaseUrl: env('PUBLIC_BASE_URL', 'http://localhost:8080'),
  publicWsUrl: env('PUBLIC_WS_URL', 'ws://localhost:8080/ws/agent'),
  commandDefaultTtlSeconds: envInt('COMMAND_DEFAULT_TTL_SECONDS', 900),
  commandMaxRunningSeconds: envInt('COMMAND_MAX_RUNNING_SECONDS', 86400),
  heartbeatIntervalSeconds: envInt('HEARTBEAT_INTERVAL_SECONDS', 30),
  offlineAfterSeconds: envInt('OFFLINE_AFTER_SECONDS', 90),
  maxAgentMessageBytes: envInt('MAX_AGENT_MESSAGE_BYTES', 1024 * 1024),
  maxCliOutputBytes: envInt('MAX_CLI_OUTPUT_BYTES', 64 * 1024),
  webhookTimeoutMs: envInt('WEBHOOK_TIMEOUT_MS', 8000),
  webhookMaxAttempts: envInt('WEBHOOK_MAX_ATTEMPTS', 8),
  eventRetentionDays: envInt('EVENT_RETENTION_DAYS', 90),
  retentionCleanupIntervalSeconds: envInt('RETENTION_CLEANUP_INTERVAL_SECONDS', 3600),
  serviceHost: env('SERVICE_HOST', '0.0.0.0'),
  msAPort: envInt('MS_A_PORT', 8081),
  msBPort: envInt('MS_B_PORT', 8082),
  msCPort: envInt('MS_C_PORT', 8083),
  graphqlMaxBodyBytes: envInt('GRAPHQL_MAX_BODY_BYTES', 1024 * 1024),
  graphqlRequestsPerMinute: envInt('GRAPHQL_REQUESTS_PER_MINUTE', 300),
  websocketUpgradesPerMinute: envInt('WEBSOCKET_UPGRADES_PER_MINUTE', 120),
  graphqlMaxDepth: envInt('GRAPHQL_MAX_DEPTH', 10),
  graphqlMaxFields: envInt('GRAPHQL_MAX_FIELDS', 250),
  graphqlAllowIntrospection: envBool('GRAPHQL_ALLOW_INTROSPECTION', false),
  webhookAllowHttp: envBool('WEBHOOK_ALLOW_HTTP', false),
  webhookAllowedHosts: csvEnv('WEBHOOK_ALLOWED_HOSTS', []),
  approvedAgentVersion: env('APPROVED_AGENT_VERSION', '3.0.0-RC'),
});
