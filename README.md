# medusa-deploy

Production deployment of [MedusaJS 2](https://medusajs.com) on a single VPS with Docker Compose. The app code comes from Medusa's official [`dtc-starter`](https://github.com/medusajs/dtc-starter); this repo adds the images, stack, and operations around it.

| Service | Role |
|---|---|
| `nginx` | TLS, rate limits, routing. Only service with public ports. |
| `storefront` | Next.js shop at `https://DOMAIN` |
| `medusa-server` | Store API and admin at `https://api.DOMAIN` |
| `medusa-worker` | Subscribers and scheduled jobs. Same image as the server. |
| `migrate` | One-shot. Runs before the server and worker start. |
| `postgres` | Primary database |
| `redis-queue` | Queues, sessions, locks (`noeviction`, persistent) |
| `redis-cache` | Disposable cache (`allkeys-lru`) |
| `certbot` | Renews the Let's Encrypt certificate |

## Local development

Requires Node 24 and pnpm 10.

```bash
pnpm install
make dev-up                    # Postgres, Redis, Mailpit on localhost
cp apps/backend/.env.template apps/backend/.env
cp apps/storefront/.env.template apps/storefront/.env.local
pnpm backend:dev               # API + admin on :9000
pnpm storefront:dev            # shop on :8000
```

## Tests

CI runs all of these on every pull request and push to `main`.

| Suite | What it checks | Run locally |
|---|---|---|
| Lint | ESLint for both apps, shellcheck, compose file | `pnpm lint` |
| Backend unit | Search index helpers | `pnpm --filter @medusa-deploy/backend test:unit` |
| Backend HTTP | Store API, publishable keys, product search against a real Postgres | `pnpm --filter @medusa-deploy/backend test:integration:http`, with `DB_HOST`, `DB_USERNAME` and `DB_PASSWORD` set |
| Stack smoke test | A full first deploy with both images: nginx routing and TLS, store API, search, backup and restore, automatic rollback | `infra/tests/smoke.sh` on a machine with Docker and no `.env` |

Backend unit tests live in `apps/backend/src/__tests__`, not next to the code: Medusa loads every file under folders such as `src/search` at startup. The HTTP tests need Postgres on `localhost`, because Medusa's test runner turns on SSL for any other host.

## Documentation

- [docs/architecture.md](docs/architecture.md): how the stack fits together, and why
- [docs/deployment.md](docs/deployment.md): server setup, releases, rollback, backups, troubleshooting
