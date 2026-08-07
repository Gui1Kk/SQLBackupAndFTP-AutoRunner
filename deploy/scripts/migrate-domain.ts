import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../../services/shared/src/db.ts';

const here = path.dirname(fileURLToPath(import.meta.url));
const migration = path.resolve(here, '../postgres/init/001_control_plane.sql');
const sql = await fs.readFile(migration, 'utf8');
await pool.query(sql);
console.log(JSON.stringify({ ok: true, migration: '001_control_plane' }));
await pool.end();
