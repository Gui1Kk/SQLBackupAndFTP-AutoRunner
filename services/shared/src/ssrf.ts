import dns from 'node:dns/promises';
import net from 'node:net';
import { config } from './config.ts';
import { DomainError } from './problem.ts';

export function isBlockedIp(ip) {
  if (net.isIPv4(ip)) {
    const p = ip.split('.').map(Number);
    return p[0] === 10 || p[0] === 127 || p[0] === 0 || p[0] >= 224 ||
      (p[0] === 169 && p[1] === 254) || (p[0] === 172 && p[1] >= 16 && p[1] <= 31) ||
      (p[0] === 192 && p[1] === 168) || (p[0] === 100 && p[1] >= 64 && p[1] <= 127) ||
      (p[0] === 192 && p[1] === 0 && p[2] <= 2) || (p[0] === 198 && (p[1] === 18 || p[1] === 19 || p[1] === 51)) ||
      (p[0] === 203 && p[1] === 0 && p[2] === 113);
  }
  const x = ip.toLowerCase();
  if(x.startsWith('::ffff:')){const mapped=x.slice(7);return net.isIPv4(mapped)?isBlockedIp(mapped):true;}
  return x === '::1' || x === '::' || x.startsWith('fe8') || x.startsWith('fe9') || x.startsWith('fea') || x.startsWith('feb') ||
    x.startsWith('fc') || x.startsWith('fd') || x.startsWith('ff') || x.startsWith('2001:db8:');
}

export async function resolveWebhookTarget(input) {
  let url;
  try { url = new URL(String(input)); } catch { throw new DomainError('WEBHOOK_URL_INVALID','URL de webhook inválida.',400); }
  if (url.username || url.password) throw new DomainError('WEBHOOK_URL_INVALID','Credenciais na URL não são permitidas.',400);
  if (url.protocol !== 'https:' && !(config.webhookAllowHttp && url.protocol === 'http:')) {
    throw new DomainError('WEBHOOK_HTTPS_REQUIRED','Webhook deve usar HTTPS.',400);
  }
  const host=url.hostname.toLowerCase();
  const explicitlyAllowed=config.webhookAllowedHosts.map((x)=>x.toLowerCase()).includes(host);
  if (!explicitlyAllowed && ['localhost','localhost.localdomain'].includes(host)) throw new DomainError('WEBHOOK_SSRF_BLOCKED','Destino local bloqueado.',400);
  const addresses = await dns.lookup(url.hostname, { all: true, verbatim: true });
  if (!addresses.length) throw new DomainError('WEBHOOK_DNS_FAILED','Destino não resolveu DNS.',400);
  const acceptable=addresses.filter((x)=>explicitlyAllowed || !isBlockedIp(x.address));
  if (!acceptable.length || (!explicitlyAllowed && acceptable.length !== addresses.length)) throw new DomainError('WEBHOOK_SSRF_BLOCKED','Destino privado/reservado bloqueado.',400);
  // O IP retornado é reutilizado na conexão HTTP. Isso fecha a janela clássica de
  // DNS rebinding entre a validação SSRF e a abertura do socket.
  return { url, address: acceptable[0].address, family: acceptable[0].family, explicitlyAllowed };
}

export async function validateWebhookUrl(input) {
  return (await resolveWebhookTarget(input)).url;
}
