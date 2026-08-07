export function encodeCursor(row) {
  return Buffer.from(JSON.stringify([row.created_at ?? row.createdAt ?? null, row.id]), 'utf8').toString('base64url');
}
export function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    const value = JSON.parse(Buffer.from(String(cursor), 'base64url').toString('utf8'));
    return Array.isArray(value) && value.length === 2 ? { createdAt: value[0], id: value[1] } : null;
  } catch { return null; }
}
export function clampPageSize(value, fallback = 50, max = 200) {
  const n = Number.parseInt(String(value ?? fallback), 10);
  return Number.isFinite(n) ? Math.max(1, Math.min(n, max)) : fallback;
}
