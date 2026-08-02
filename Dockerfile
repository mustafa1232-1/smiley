FROM node:22-bookworm-slim AS build

WORKDIR /app/backend

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY backend/package*.json ./
RUN npm ci

COPY backend/prisma ./prisma
RUN npx prisma generate

COPY backend ./
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime

WORKDIR /app/backend
ENV NODE_ENV=production

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/backend/package*.json ./
COPY --from=build /app/backend/node_modules ./node_modules
COPY --from=build /app/backend/dist ./dist
COPY --from=build /app/backend/prisma ./prisma

EXPOSE 3000

CMD ["npm", "run", "start"]
