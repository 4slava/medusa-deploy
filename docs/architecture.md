# Architecture

```
Internet ──▶ nginx :80 :443
               ├── DOMAIN      ──▶ storefront :8000 ──┐ (server rendering)
               └── api.DOMAIN  ──▶ medusa-server :9000 ◀┘
                                        │
   medusa-worker ◀── redis-queue ◀──────┤
        │                               │
        └────────▶ postgres ◀───────────┘
                   redis-cache
```

Two Docker networks separate the tiers. `edge` holds nginx, the storefront, the server and the worker. `data` holds Postgres and Redis, and is `internal`, so those services have no route to the internet. Only nginx publishes ports.

Medusa is a modular monolith, so this is one application running in two modes, not a set of microservices. `MEDUSA_WORKER_MODE` selects the mode.

## Request flow

- **Server rendering** calls `http://medusa-server:9000` over the private network (`MEDUSA_INTERNAL_BACKEND_URL`), so it does not pass through nginx rate limits.
- **The browser** calls `https://api.DOMAIN` directly for product search, using the publishable key.
- **Events** go from the server to the worker through `redis-queue`. Subscribers run only on the worker.

## Decisions

### Image is built off the server
A Medusa and Next.js build needs more memory than a 2 GB VPS has to spare. Images are built in CI or on a workstation.

### One backend image, no runtime configuration baked in
The admin uses a relative API URL, so the same backend image works on any domain.

### Storefront image is tied to one environment
Next.js inlines `NEXT_PUBLIC_*` at build time, and browser search needs the API URL and publishable key. The key is created by the first migration, so a first deploy starts the backend, reads the key, and only then builds the storefront.

### Two Redis instances
BullMQ requires `noeviction`, or queued jobs can be lost under memory pressure, while a cache needs eviction. The policy applies per Redis instance, so separate logical databases would not work.

### Migrations run as a one-shot service
`migrate` must exit cleanly before the server and worker start, so they never race a migration and every `compose up` applies pending ones.

### Uploads on a shared volume until S3 is configured
Files live in the `uploads` volume, mounted into the server and worker. Setting `S3_BUCKET` switches to S3-compatible storage. Moving to more than one host requires S3.

### Postgres 17
The Postgres 18 image moved its data directory, and nothing here needs 18.

### Storefront base
`nextjs-starter-medusa` is deprecated. `dtc-starter` is what `create-medusa-app` uses now.

## Scaling

| Signal | Action |
|---|---|
| Memory or swap under sustained pressure | Larger VPS, then raise the limits in `docker-compose.yml` |
| Slow background jobs | More worker replicas on the same host |
| Database load or backup burden | Managed Postgres (change `DATABASE_URL`) |
| Need for a second host | Move to S3, then managed Postgres and Redis, then Kubernetes with Gateway API |

`ingress-nginx` was retired in March 2026, so do not use it for a Kubernetes move.
