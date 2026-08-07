const SECRET_KEYS = /password|passwd|pwd|secret|token|authorization|api[-_]?key|connectionstring|credential|privatekey|accesskey/i;
const CONNECTION_STRING = /((?:password|pwd)\s*=\s*)[^;\s]+/ig;
const BEARER = /(bearer\s+)[A-Za-z0-9._~+\/-]+=*/ig;
const API_KEY = /(x-api-key\s*[:=]\s*)[^\s,;]+/ig;

export function redactText(value, maxBytes = 65536) {
  let text = String(value ?? '')
    .replace(CONNECTION_STRING, '$1***REDACTED***')
    .replace(BEARER, '$1***REDACTED***')
    .replace(API_KEY, '$1***REDACTED***');
  const buffer = Buffer.from(text, 'utf8');
  if (buffer.length > maxBytes) text = buffer.subarray(0, maxBytes).toString('utf8') + '\n...[TRUNCATED]';
  return text;
}

export function redactObject(value, depth = 0) {
  if (depth > 12) return '[DEPTH_LIMIT]';
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return redactText(value);
  if (typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.slice(0, 500).map((item) => redactObject(item, depth + 1));
  const out = {};
  for (const [key, item] of Object.entries(value)) {
    out[key] = SECRET_KEYS.test(key) ? '***REDACTED***' : redactObject(item, depth + 1);
  }
  return out;
}
