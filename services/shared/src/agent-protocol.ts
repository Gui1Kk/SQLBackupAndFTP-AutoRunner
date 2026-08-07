import crypto from 'node:crypto';

export const PROTOCOL_VERSION = 1;
export const AGENT_MESSAGE_TYPES = new Set([
  'hello', 'heartbeat', 'inventory.snapshot', 'inventory.changed',
  'command.accepted', 'command.rejected', 'command.progress', 'command.completed',
  'execution.started', 'execution.completed', 'diagnostic.completed', 'agent.updating'
]);

export const SERVER_MESSAGE_TYPES = new Set([
  'welcome', 'ping', 'command.executeJob', 'command.refreshInventory',
  'command.collectDiagnostics', 'command.updateAgent', 'command.cancel', 'session.revoke'
]);

export function envelope(type, payload = {}, correlationId = null) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    messageId: crypto.randomUUID(),
    type,
    sentAt: new Date().toISOString(),
    correlationId,
    payload,
  };
}

export function validateEnvelope(message, allowedTypes) {
  if (!message || typeof message !== 'object') return 'Envelope deve ser objeto.';
  if (message.protocolVersion !== PROTOCOL_VERSION) return 'Versão de protocolo não suportada.';
  if (typeof message.messageId !== 'string' || message.messageId.length < 8) return 'messageId inválido.';
  if (!allowedTypes.has(message.type)) return `Tipo de mensagem não suportado: ${message.type}`;
  if (!message.sentAt || Number.isNaN(Date.parse(message.sentAt))) return 'sentAt inválido.';
  if (message.payload !== undefined && (message.payload === null || typeof message.payload !== 'object')) return 'payload inválido.';
  return null;
}
