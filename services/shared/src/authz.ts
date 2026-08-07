import { auth } from '../../ms-a-rest/src/auth.ts';
import { fromNodeHeaders } from 'better-auth/node';
import { one } from './db.ts';
import { DomainError } from './problem.ts';


function headerValue(headers, name) {
  if (!headers) return null;
  if (typeof headers.get === 'function') return headers.get(name) || headers.get(name.toLowerCase()) || null;
  const value = headers[name.toLowerCase()] ?? headers[name] ?? null;
  return Array.isArray(value) ? value[0] : value;
}

function betterAuthHeaders(headers) {
  if (headers && typeof headers.get === 'function') return headers;
  return fromNodeHeaders(headers || {});
}

const ROLE_PERMISSIONS = {
  platform_owner: ['*'],
  support_admin: [
    'clients:read','clients:manage','machines:read','machines:manage','agents:read','agents:enroll','agents:revoke','agents:update',
    'jobs:read','jobs:execute','jobs:create','jobs:update','jobs:delete','executions:read','executions:cancel','diagnostics:read','diagnostics:request',
    'webhooks:read','webhooks:manage','audit:read','integrations:manage'
  ],
  support_operator: ['clients:read','machines:read','agents:read','jobs:read','jobs:execute','executions:read','diagnostics:read','diagnostics:request'],
  viewer: ['clients:read','machines:read','agents:read','jobs:read','executions:read'],
  auditor: ['clients:read','machines:read','agents:read','jobs:read','executions:read','audit:read'],
};

function hasPermission(role, permission) {
  const list = ROLE_PERMISSIONS[role] || [];
  return list.includes('*') || list.includes(permission);
}

async function authFromApiKey(request) {
  const key = headerValue(request.headers, 'x-api-key');
  if (!key) return null;
  const verified = await auth.api.verifyApiKey({ body: { configId: 'integration', key } });
  if (!verified?.valid || !verified.key) return null;
  const metadata = verified.key.metadata && typeof verified.key.metadata === 'object' ? verified.key.metadata : {};
  let organizationId = metadata.organizationId || null;
  if (!organizationId && verified.key.referenceId) {
    const mapped = await one(`select id from ar_organizations where auth_organization_id=$1 limit 1`, [verified.key.referenceId]);
    organizationId = mapped?.id || null;
  }
  if (!organizationId) return null;
  return {
    actorType: 'integration',
    actorId: verified.key.id,
    userId: null,
    organizationId,
    role: 'integration',
    permissions: verified.key.permissions || metadata.permissions || {},
    authMethod: 'api_key',
  };
}

function apiKeyHasPermission(principal, permission) {
  const [resource, action] = permission.split(':');
  const permissions = principal.permissions || {};
  if (Array.isArray(permissions)) return permissions.includes('*') || permissions.includes(permission);
  const actions = permissions[resource] || [];
  return actions.includes('*') || actions.includes(action);
}

export async function getPrincipal(request) {
  try {
    const apiPrincipal = await authFromApiKey(request);
    if (apiPrincipal) return apiPrincipal;
  } catch {}

  const session = await auth.api.getSession({ headers: betterAuthHeaders(request.headers) });
  if (!session?.user) return null;
  const platformRole = await one(
    `select role, organization_id from ar_user_roles where user_id=$1 and active=true and role='platform_owner' order by created_at asc limit 1`,
    [session.user.id]
  );
  let role = platformRole;
  if (!role) {
    const authOrganizationId = session.session?.activeOrganizationId || null;
    if (authOrganizationId) {
      role = await one(
        `select r.role,r.organization_id from ar_user_roles r join ar_organizations o on o.id=r.organization_id where r.user_id=$1 and r.active=true and o.auth_organization_id=$2 order by r.created_at asc limit 1`,
        [session.user.id, authOrganizationId]
      );
    }
    if (!role) {
      role = await one(
        `select role,organization_id from ar_user_roles where user_id=$1 and active=true order by created_at asc limit 1`,
        [session.user.id]
      );
    }
  }
  return {
    actorType: 'user',
    actorId: session.user.id,
    userId: session.user.id,
    email: session.user.email,
    organizationId: role?.organization_id || null,
    role: role?.role || 'viewer',
    authMethod: 'session',
  };
}

export async function requirePrincipal(request, permission, resourceOrganizationId = null) {
  const principal = await getPrincipal(request);
  if (!principal) throw new DomainError('UNAUTHENTICATED', 'Autenticação obrigatória.', 401);

  const permitted = principal.authMethod === 'api_key'
    ? apiKeyHasPermission(principal, permission)
    : hasPermission(principal.role, permission);
  if (!permitted) throw new DomainError('FORBIDDEN_SCOPE', `Permissão ausente: ${permission}`, 403);

  if (resourceOrganizationId && principal.role !== 'platform_owner' && principal.organizationId !== resourceOrganizationId) {
    throw new DomainError('FORBIDDEN_SCOPE', 'O recurso pertence a outra organização.', 403);
  }
  return principal;
}

export async function resolveOrganizationScope(principal, requestedOrganizationId = null) {
  if (principal.role === 'platform_owner') return requestedOrganizationId || null;
  if (!principal.organizationId) throw new DomainError('FORBIDDEN_SCOPE', 'Usuário sem organização vinculada.', 403);
  if (requestedOrganizationId && requestedOrganizationId !== principal.organizationId) {
    throw new DomainError('FORBIDDEN_SCOPE', 'Organização fora do escopo.', 403);
  }
  return principal.organizationId;
}
