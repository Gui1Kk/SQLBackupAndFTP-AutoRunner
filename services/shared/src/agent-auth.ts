import { one } from './db.ts';
import { hashAgentSecret, timingSafeHexEqual } from './crypto.ts';

export function parseAgentAuthorization(header) {
  const match = /^Agent\s+([0-9a-f-]{36})\.([A-Za-z0-9_-]{32,})$/i.exec(String(header || '').trim());
  return match ? { agentId: match[1], secret: match[2] } : null;
}
export async function authenticateAgent(header) {
  const parsed = parseAgentAuthorization(header);
  if (!parsed) return null;
  const agent = await one(
    `select a.*,m.client_id,c.organization_id,m.display_name,m.hostname from ar_agents a
     join ar_machines m on m.id=a.machine_id join ar_clients c on c.id=m.client_id where a.id=$1`, [parsed.agentId]
  );
  if (!agent || ['revoked','blocked'].includes(agent.status)) return null;
  const calculated = hashAgentSecret(parsed.secret);
  if (!timingSafeHexEqual(calculated, agent.secret_hash)) return null;
  return agent;
}
