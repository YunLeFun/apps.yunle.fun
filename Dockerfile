FROM node:22-alpine AS build-stage

WORKDIR /app
RUN corepack enable

COPY .npmrc package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY docs/package.json ./docs/package.json
COPY patches ./patches
RUN --mount=type=cache,id=pnpm-store,target=/root/.pnpm-store \
    pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

# SSR
FROM node:22-alpine AS production-stage

WORKDIR /app

COPY --from=build-stage /app/.output ./.output
COPY --from=build-stage /app/package.json ./

# 腾讯云云函数的端口号是 9000
# NUXT_PORT not work
ENV NITRO_PORT 80

EXPOSE 80

CMD ["node", ".output/server/index.mjs"]
