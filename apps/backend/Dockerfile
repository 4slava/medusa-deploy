# One image, two roles: MEDUSA_WORKER_MODE selects server or worker at runtime.
# Build from the repo root: docker build -f apps/backend/Dockerfile .

FROM node:24.22-alpine AS build
ENV CI=true MEDUSA_DISABLE_TELEMETRY=true
RUN corepack enable && corepack prepare pnpm@10.11.1 --activate
WORKDIR /repo

# Manifests first so dependency layers survive source changes
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY apps/backend/package.json apps/backend/
COPY apps/storefront/package.json apps/storefront/
RUN pnpm install --frozen-lockfile --filter @medusa-deploy/backend...

COPY apps/backend apps/backend
RUN pnpm --filter @medusa-deploy/backend build

# Second, runtime-only install from the same lockfile. pnpm's symlinks are
# relative, so the runner must keep this repo layout.
RUN mkdir -p /prod/apps/backend /prod/apps/storefront \
 && cp package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc /prod/ \
 && cp apps/backend/package.json /prod/apps/backend/ \
 && cp apps/storefront/package.json /prod/apps/storefront/ \
 && cd /prod \
 && pnpm install --frozen-lockfile --prod --filter @medusa-deploy/backend...

FROM node:24.22-alpine AS runner
ENV NODE_ENV=production MEDUSA_DISABLE_TELEMETRY=true PORT=9000
WORKDIR /app/apps/backend

COPY --from=build --chown=node:node /prod/node_modules /app/node_modules
COPY --from=build --chown=node:node /prod/apps/backend/node_modules ./node_modules
COPY --from=build --chown=node:node /repo/apps/backend/.medusa/server ./

# Mount point for the shared uploads volume
RUN mkdir -p static && chown node:node static

USER node
EXPOSE 9000
CMD ["node_modules/.bin/medusa", "start"]
