export function log(level, msg, fields = {}) {
  const record = {
    ts: new Date().toISOString(),
    level,
    service: process.env.SERVICE_NAME || 'unknown',
    msg,
    ...fields,
  };
  const line = JSON.stringify(record);
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.log(line);
}
