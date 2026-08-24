# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS base
WORKDIR /app

FROM base AS builder

RUN apk --no-cache upgrade && \
  apk --no-cache add python3 make g++ linux-headers

COPY package.json ./

RUN --mount=type=cache,target=/root/.npm \
  npm install

COPY . ./

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build


FROM ${NODE_IMAGE} AS runner

WORKDIR /app

LABEL org.opencontainers.image.title="9router"

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1
ENV DATA_DIR=/app/data

# ---------------------------------------------------------
# Application
# ---------------------------------------------------------

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/custom-server.js ./custom-server.js
COPY --from=builder /app/open-sse ./open-sse

# MITM
COPY --from=builder /app/src/mitm ./src/mitm

# Runtime dependencies
COPY --from=builder /app/node_modules/node-forge ./node_modules/node-forge
COPY --from=builder /app/node_modules/next ./node_modules/next
COPY --from=builder /app/node_modules/sql.js ./node_modules/sql.js

# ---------------------------------------------------------
# Persistence / Tools
# ---------------------------------------------------------

RUN apk --no-cache upgrade && \
  apk --no-cache add \
  su-exec \
  aws-cli \
  sqlite \
  tar \
  gzip

# Data directories
RUN mkdir -p \
  /app/data \
  /app/data-home \
  /app/scripts \
  && \
  chown -R node:node /app

# Keep 9Router data paths available
RUN ln -sf /app/data /app/data-home/.9router 2>/dev/null || true

# ---------------------------------------------------------
# Scripts
# ---------------------------------------------------------

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/backup.sh /app/scripts/backup.sh

RUN chmod +x \
  /entrypoint.sh \
  /app/scripts/backup.sh \
  && \
  chown node:node \
  /entrypoint.sh \
  /app/scripts/backup.sh

# ---------------------------------------------------------
# Runtime
# ---------------------------------------------------------

EXPOSE 20128

ENTRYPOINT ["/entrypoint.sh"]

CMD ["node", "custom-server.js"]