import { betterAuth } from 'better-auth';
import { organization, openAPI } from 'better-auth/plugins';
import { apiKey } from '@better-auth/api-key';
import pg from 'pg';
import { config } from '../../shared/src/config.ts';

const { Pool } = pg;
export const authPool = new Pool({
  connectionString: config.databaseUrl,
  max: 10,
  application_name: 'autorunner-better-auth',
});

export const auth = betterAuth({
  database: authPool,
  baseURL: config.betterAuthUrl,
  secret: config.betterAuthSecret,
  trustedOrigins: config.trustedOrigins,
  emailAndPassword: {
    enabled: true,
    disableSignUp: !config.allowPublicSignup,
    minPasswordLength: 12,
    maxPasswordLength: 128,
    autoSignIn: true,
  },
  session: {
    expiresIn: 60 * 60 * 12,
    updateAge: 60 * 30,
    cookieCache: {
      enabled: true,
      maxAge: 60 * 5,
    },
  },
  advanced: {
    useSecureCookies: config.publicBaseUrl.startsWith('https://'),
    cookiePrefix: 'autorunner',
  },
  rateLimit: {
    enabled: true,
    window: 60,
    max: 100,
  },
  plugins: [
    organization({
      allowUserToCreateOrganization: async (user) => {
        try {
          const result = await authPool.query(
            `select 1 from ar_user_roles where user_id=$1 and role='platform_owner' and active=true limit 1`,
            [user.id]
          );
          return result.rowCount > 0;
        } catch {
          return false;
        }
      },
      disableOrganizationDeletion: true,
    }),
    apiKey([{
      configId: 'integration',
      references: 'organization',
      apiKeyHeaders: ['x-api-key'],
      defaultPrefix: 'ar_',
      enableMetadata: true,
      permissions: { defaultPermissions: {} },
    }]),
    openAPI(),
  ],
});
