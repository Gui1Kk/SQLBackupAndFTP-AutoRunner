import { auth } from '../../services/ms-a-rest/src/auth.ts';
import { pool } from '../../services/shared/src/db.ts';
import { normalizeSlug } from '../../services/shared/src/ids.ts';

const email = process.env.BOOTSTRAP_ADMIN_EMAIL;
const password = process.env.BOOTSTRAP_ADMIN_PASSWORD;
const name = process.env.BOOTSTRAP_ADMIN_NAME || 'Administrador';
const orgName = process.env.BOOTSTRAP_ORGANIZATION_NAME || 'Alpha Software';
if (!email || !password || password.length < 12) {
  throw new Error('Defina BOOTSTRAP_ADMIN_EMAIL e BOOTSTRAP_ADMIN_PASSWORD (mínimo 12 caracteres).');
}

let userId = null;
try {
  const created = await auth.api.signUpEmail({ body: { email, password, name } });
  userId = created?.user?.id || created?.id || null;
} catch (error) {
  const existing = await pool.query(`select id from "user" where lower(email)=lower($1) limit 1`, [email]);
  userId = existing.rows[0]?.id || null;
  if (!userId) throw error;
}
if (!userId) throw new Error('Não foi possível determinar o usuário bootstrap.');

await pool.query(
  `insert into ar_user_roles(user_id, organization_id, role, active)
   select $1,null,'platform_owner',true
   where not exists (
     select 1 from ar_user_roles where user_id=$1 and organization_id is null and role='platform_owner'
   )`,
  [userId]
);
await pool.query(
  `update ar_user_roles set active=true where user_id=$1 and organization_id is null and role='platform_owner'`,
  [userId]
);

let organization = null;
try {
  organization = await auth.api.createOrganization({
    body: { name: orgName, slug: normalizeSlug(orgName), userId, keepCurrentActiveOrganization: false },
  });
} catch {
  const existing = await pool.query(`select id,name,slug from organization where slug=$1 limit 1`, [normalizeSlug(orgName)]);
  organization = existing.rows[0] || null;
}
if (organization?.id) {
  await pool.query(
    `insert into ar_organizations(auth_organization_id,name,slug,status)
     values($1,$2,$3,'active')
     on conflict (slug) do update set auth_organization_id=excluded.auth_organization_id, name=excluded.name, updated_at=now()`,
    [organization.id, orgName, normalizeSlug(orgName)]
  );
}
console.log(JSON.stringify({ ok: true, userId, organizationId: organization?.id || null, email }));
await pool.end();
await authPoolEnd();

async function authPoolEnd() {
  try {
    const { authPool } = await import('../../services/ms-a-rest/src/auth.ts');
    await authPool.end();
  } catch {}
}
