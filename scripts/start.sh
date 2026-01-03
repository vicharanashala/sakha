#!/bin/sh
set -e

echo "Starting Tailscale..."

# Start Tailscale daemon
/app/tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
sleep 3

# Authenticate
/app/tailscale up \
  --auth-key="${TAILSCALE_AUTHKEY}" \
  --hostname=librechat-cloudrun \
  --accept-dns=false

# Configure proxy
export ALL_PROXY="socks5://localhost:1055"
export HTTP_PROXY="$ALL_PROXY"
export HTTPS_PROXY="$ALL_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1,raw.githubusercontent.com,github.com,metadata.google.internal,169.254.169.254"

# Authenticate with Infisical
echo "Authenticating with Infisical..."
export INFISICAL_TOKEN=$(
  infisical login \
    --method=universal-auth \
    --client-id="$INFISICAL_CLIENT_ID" \
    --client-secret="$INFISICAL_CLIENT_SECRET" \
    --silent \
    --plain
)

[ -z "$INFISICAL_TOKEN" ] && echo "✗ Infisical auth failed" && exit 1

# Start LibreChat
echo "Starting LibreChat..."
exec proxychains4 -q infisical run \
  --env=prod \
  --projectId="$INFISICAL_PROJECT_ID" \
  --path="$INFISICAL_ENV_PATH" \
  -- npm run backend
