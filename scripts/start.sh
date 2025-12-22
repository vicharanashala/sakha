#!/bin/sh
set -e

echo "▶ Starting Tailscale..."

# Start Tailscale daemon (userspace)
 /app/tailscaled \
  --tun=userspace-networking \
  --socks5-server=localhost:1055 &

# Give it a moment
sleep 2

# Authenticate
/app/tailscale up \
  --auth-key="${TAILSCALE_AUTHKEY}" \
  --hostname=librechat-cloudrun \
  --accept-dns=false

echo "✅ Tailscale connected"

# Tailscale SOCKS proxy
SOCKS_PROXY="socks5://localhost:1055"

export ALL_PROXY="$SOCKS_PROXY"
export HTTP_PROXY="$SOCKS_PROXY"
export HTTPS_PROXY="$SOCKS_PROXY"
export PROXY="$SOCKS_PROXY"

export NO_PROXY="localhost,127.0.0.1,::1,raw.githubusercontent.com,github.com,metadata.google.internal,169.254.169.254"

# ---- Infisical auth ----
echo "▶ Authenticating with Infisical..."

export INFISICAL_TOKEN=$(
  infisical login \
    --method=universal-auth \
    --client-id="$INFISICAL_CLIENT_ID" \
    --client-secret="$INFISICAL_CLIENT_SECRET" \
    --silent \
    --plain
)

echo "✅ Infisical authenticated"

# ---- Start LibreChat with secrets injected ----
echo "▶ Starting LibreChat with Infisical secrets..."

exec infisical run \
  --env=prod \
  --projectId="$INFISICAL_PROJECT_ID" \
  --path="$INFISICAL_ENV_PATH" \
  -- npm run backend
