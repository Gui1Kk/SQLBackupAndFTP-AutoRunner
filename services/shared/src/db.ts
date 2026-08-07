import pg from 'pg';
import { config } from './config.ts';

const { Pool } = pg;
export const pool = new Pool({
  connectionString: config.databaseUrl,
  max: Number.parseInt(process.env.DB_POOL_MAX || '20', 10),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  application_name: process.env.SERVICE_NAME || 'autorunner-control-plane',
});

pool.on('error', (error) => {
  console.error(JSON.stringify({ level: 'error', msg: 'postgres_pool_error', error: error.message }));
});

export async function query(text, params = []) {
  return pool.query(text, params);
}

export async function one(text, params = []) {
  const result = await pool.query(text, params);
  return result.rows[0] ?? null;
}

export async function many(text, params = []) {
  const result = await pool.query(text, params);
  return result.rows;
}

export async function tx(callback) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch {}
    throw error;
  } finally {
    client.release();
  }
}

export async function databaseReady() {
  try {
    const result = await pool.query('select 1 as ok');
    return result.rows[0]?.ok === 1;
  } catch {
    return false;
  }
}
