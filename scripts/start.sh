#!/bin/sh
set -e

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  TAILSCALE STARTUP DIAGNOSTICS"
echo "════════════════════════════════════════════════════════════"
echo ""

# ============================================================
# STEP 1: Start Tailscale Daemon
# ============================================================
echo "▶ [1/7] Starting Tailscale daemon..."
/app/tailscaled \
  --tun=userspace-networking \
  --socks5-server=localhost:1055 \
  --verbose=1 &

TAILSCALED_PID=$!
echo "   ✓ Tailscaled started (PID: $TAILSCALED_PID)"
sleep 3

# ============================================================
# STEP 2: Authenticate with Tailscale
# ============================================================
echo ""
echo "▶ [2/7] Authenticating with Tailscale..."
/app/tailscale up \
  --auth-key="${TAILSCALE_AUTHKEY}" \
  --hostname=librechat-cloudrun \
  --accept-dns=false

if [ $? -eq 0 ]; then
  echo "   ✓ Tailscale authentication successful"
else
  echo "   ✗ Tailscale authentication failed"
  exit 1
fi

# ============================================================
# STEP 3: Wait for Backend to be Running
# ============================================================
echo ""
echo "▶ [3/7] Waiting for Tailscale backend to initialize..."
RETRY_COUNT=0
MAX_RETRIES=10

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Check if tailscale status returns successfully (exit code 0)
  if /app/tailscale status >/dev/null 2>&1; then
    # Also verify we have our own Tailscale IP assigned
    TAILSCALE_IP=$(/app/tailscale ip -4 2>/dev/null || echo "")
    
    if [ -n "$TAILSCALE_IP" ]; then
      echo "   ✓ Tailscale backend is Running (took ${RETRY_COUNT}s)"
      echo "   ✓ Assigned Tailscale IP: $TAILSCALE_IP"
      break
    else
      echo "   ⏳ Waiting for IP assignment... (${RETRY_COUNT}/${MAX_RETRIES}s)"
    fi
  else
    echo "   ⏳ Backend initializing... (${RETRY_COUNT}/${MAX_RETRIES}s)"
  fi
  
  sleep 1
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "   ✗ Tailscale backend failed to start within ${MAX_RETRIES} seconds"
  echo ""
  echo "Current Tailscale status:"
  /app/tailscale status
  exit 1
fi

# ============================================================
# STEP 4: Wait for Peer Connections
# ============================================================
# echo ""
# echo "▶ [4/7] Waiting for peer connections to stabilize..."
# echo "   (Giving network 15 seconds to establish connections)"

# for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
#   echo "   ⏳ ${i}/15 seconds..."
#   sleep 1
# done

# echo "   ✓ Stabilization period complete"

# ============================================================
# STEP 5: Display Tailscale Status
# ============================================================
echo ""
echo "▶ [5/7] Current Tailscale Status:"
echo "────────────────────────────────────────────────────────────"
/app/tailscale status | head -20  # Show first 20 lines to avoid clutter
echo "   ... (showing first 20 peers)"
echo "────────────────────────────────────────────────────────────"

# ============================================================
# STEP 6: Configure Proxy Environment
# ============================================================
echo ""
echo "▶ [6/7] Configuring proxy environment..."
SOCKS_PROXY="socks5://localhost:1055"
export ALL_PROXY="$SOCKS_PROXY"
export HTTP_PROXY="$SOCKS_PROXY"
export HTTPS_PROXY="$SOCKS_PROXY"
export PROXY="$SOCKS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1,raw.githubusercontent.com,github.com,metadata.google.internal,169.254.169.254"

echo "   ✓ Proxy configured: $SOCKS_PROXY"

# ============================================================
# STEP 7: Infisical Authentication
# ============================================================
echo ""
echo "▶ [7/7] Authenticating with Infisical..."
export INFISICAL_TOKEN=$(
  infisical login \
    --method=universal-auth \
    --client-id="$INFISICAL_CLIENT_ID" \
    --client-secret="$INFISICAL_CLIENT_SECRET" \
    --silent \
    --plain
)

if [ -n "$INFISICAL_TOKEN" ]; then
  echo "   ✓ Infisical authenticated"
else
  echo "   ✗ Infisical authentication failed"
  exit 1
fi

# ============================================================
# START LIBRECHAT
# ============================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  STARTING LIBRECHAT"
echo "════════════════════════════════════════════════════════════"
echo ""

exec proxychains4 -q infisical run \
  --env=prod \
  --projectId="$INFISICAL_PROJECT_ID" \
  --path="$INFISICAL_ENV_PATH" \
  -- npm run backend
