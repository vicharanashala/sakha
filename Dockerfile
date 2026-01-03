# v0.8.2-rc1

# Base node image
FROM node:20-bookworm-slim

# ---- System deps ----
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    gnupg \
    libjemalloc2 \
    python3 \
    python3-pip \
    proxychains4 \
    netcat-openbsd \
    iputils-ping \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*
    
RUN curl -1sLf \
'https://artifacts-cli.infisical.com/setup.deb.sh' \
| bash
RUN apt-get update && apt-get install -y infisical

# Add `uv` for extended MCP support
COPY --from=ghcr.io/astral-sh/uv:0.9.5-python3.12-alpine /usr/local/bin/uv /usr/local/bin/uvx /bin/
RUN uv --version

# ---- Tailscale binaries ----
COPY --from=docker.io/tailscale/tailscale:stable /usr/local/bin/tailscaled /app/tailscaled
COPY --from=docker.io/tailscale/tailscale:stable /usr/local/bin/tailscale /app/tailscale

# Tailscale runtime dirs
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale \
 && chown -R node:node /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

# ---- proxychains configuration ----
RUN echo "strict_chain" > /etc/proxychains4.conf && \
    echo "proxy_dns" >> /etc/proxychains4.conf && \
    echo "quiet_mode" >> /etc/proxychains4.conf && \
    echo "[ProxyList]" >> /etc/proxychains4.conf && \
    echo "socks5 127.0.0.1 1055" >> /etc/proxychains4.conf

# App setup
RUN mkdir -p /app && chown node:node /app
WORKDIR /app

USER node

COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node api/package.json ./api/package.json
COPY --chown=node:node client/package.json ./client/package.json
COPY --chown=node:node packages/data-provider/package.json ./packages/data-provider/package.json
COPY --chown=node:node packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY --chown=node:node packages/api/package.json ./packages/api/package.json

RUN \
    # Allow mounting of these files, which have no default
    touch .env ; \
    # Create directories for the volumes to inherit the correct permissions
    mkdir -p /app/client/public/images /app/logs /app/uploads ; \
    npm config set fetch-retry-maxtimeout 600000 ; \
    npm config set fetch-retries 5 ; \
    npm config set fetch-retry-mintimeout 15000 ; \
    npm ci --no-audit

COPY --chown=node:node . .

RUN \
    # React client build
    NODE_OPTIONS="--max-old-space-size=2048" npm run frontend; \
    npm prune --production; \
    npm cache clean --force

# Startup script
COPY --chown=node:node scripts/start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 3080
ENV HOST=0.0.0.0

RUN infisical --version

ENTRYPOINT []
CMD ["sh", "/app/start.sh"]
