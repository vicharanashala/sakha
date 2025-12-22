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

export NO_PROXY="localhost,127.0.0.1,::1,metadata.google.internal,169.254.169.254"

echo "▶ Starting LibreChat backend..."
exec npm run backend
