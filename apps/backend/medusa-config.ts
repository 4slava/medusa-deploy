import { loadEnv, defineConfig } from '@medusajs/framework/utils'

loadEnv(process.env.NODE_ENV || 'development', process.cwd())

const {
  REDIS_URL,
  CACHE_REDIS_URL,
  MEDUSA_BACKEND_URL,
  S3_BUCKET,
  S3_REGION,
  S3_ENDPOINT,
  S3_FILE_URL,
  S3_ACCESS_KEY_ID,
  S3_SECRET_ACCESS_KEY,
  SENDGRID_API_KEY,
  SENDGRID_FROM,
} = process.env

// Without Redis (plain local dev) Medusa falls back to its in-memory modules.
const redisModules = REDIS_URL
  ? [
      {
        resolve: '@medusajs/medusa/caching',
        options: {
          providers: [
            {
              resolve: '@medusajs/caching-redis',
              id: 'caching-redis',
              is_default: true,
              options: { redisUrl: CACHE_REDIS_URL || REDIS_URL },
            },
          ],
        },
      },
      {
        resolve: '@medusajs/medusa/event-bus-redis',
        options: { redisUrl: REDIS_URL },
      },
      {
        resolve: '@medusajs/medusa/workflow-engine-redis',
        options: { redis: { redisUrl: REDIS_URL } },
      },
      {
        resolve: '@medusajs/medusa/locking',
        options: {
          providers: [
            {
              resolve: '@medusajs/medusa/locking-redis',
              id: 'locking-redis',
              is_default: true,
              options: { redisUrl: REDIS_URL },
            },
          ],
        },
      },
    ]
  : []

// S3-compatible storage when configured, otherwise the volume shared by the
// server and worker. Local files only work while both run on one host.
const fileProvider = S3_BUCKET
  ? {
      resolve: '@medusajs/medusa/file-s3',
      id: 's3',
      options: {
        file_url: S3_FILE_URL,
        access_key_id: S3_ACCESS_KEY_ID,
        secret_access_key: S3_SECRET_ACCESS_KEY,
        region: S3_REGION,
        bucket: S3_BUCKET,
        endpoint: S3_ENDPOINT,
      },
    }
  : {
      resolve: '@medusajs/medusa/file-local',
      id: 'local',
      options: {
        upload_dir: 'static',
        backend_url: `${MEDUSA_BACKEND_URL || 'http://localhost:9000'}/static`,
      },
    }

// Until a mail provider is configured, notifications are written to the log.
const notificationProvider = SENDGRID_API_KEY
  ? {
      resolve: '@medusajs/medusa/notification-sendgrid',
      id: 'sendgrid',
      options: {
        channels: ['email'],
        api_key: SENDGRID_API_KEY,
        from: SENDGRID_FROM,
      },
    }
  : {
      resolve: '@medusajs/medusa/notification-local',
      id: 'local',
      options: { channels: ['email'] },
    }

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL,
    redisUrl: REDIS_URL,
    workerMode: (process.env.MEDUSA_WORKER_MODE || 'shared') as
      | 'shared'
      | 'server'
      | 'worker',
    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET,
      cookieSecret: process.env.COOKIE_SECRET,
    }
  },
  admin: {
    disable: process.env.DISABLE_MEDUSA_ADMIN === 'true',
  },
  modules: [
    ...redisModules,
    {
      resolve: '@medusajs/medusa/file',
      options: { providers: [fileProvider] },
    },
    {
      resolve: '@medusajs/medusa/notification',
      options: { providers: [notificationProvider] },
    },
  ],
})
