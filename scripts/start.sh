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
echo "▶ [1/8] Starting Tailscale daemon..."
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
echo "▶ [2/8] Authenticating with Tailscale..."
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
echo "▶ [3/8] Waiting for Tailscale backend to initialize..."
RETRY_COUNT=0
MAX_RETRIES=60

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
echo ""
echo "▶ [4/8] Waiting for peer connections to stabilize..."
echo "   (Giving network 15 seconds to establish connections)"

for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  echo "   ⏳ ${i}/15 seconds..."
  sleep 1
done

echo "   ✓ Stabilization period complete"

# ============================================================
# STEP 5: Display Tailscale Status
# ============================================================
echo ""
echo "▶ [5/8] Current Tailscale Status:"
echo "────────────────────────────────────────────────────────────"
/app/tailscale status | head -20  # Show first 20 lines to avoid clutter
echo "   ... (showing first 20 peers)"
echo "────────────────────────────────────────────────────────────"

# ============================================================
# STEP 6: Test MCP Server Connectivity
# ============================================================
echo ""
echo "▶ [6/8] Testing connectivity to MCP servers..."

# Your MCP server - UPDATE THIS IP if it's different!
MCP_HOST="100.100.108.13"

# Define your MCP servers
MCP_SERVERS="
$MCP_HOST:9001:golden
$MCP_HOST:9002:pop
$MCP_HOST:9003:market
$MCP_HOST:9004:weather
$MCP_HOST:9005:faq-videos
"

ALL_TESTS_PASSED=true

echo "$MCP_SERVERS" | while IFS=':' read -r HOST PORT NAME; do
  if [ -n "$HOST" ] && [ -n "$PORT" ]; then
    printf "   Testing %-12s (%s:%s)... " "$NAME" "$HOST" "$PORT"
    
    # Test with netcat through proxychains
    if timeout 5 proxychains4 -q nc -zv "$HOST" "$PORT" 2>&1 | grep -q "succeeded\|open"; then
      echo "✓ reachable"
    else
      echo "✗ NOT reachable"
      ALL_TESTS_PASSED=false
    fi
  fi
done

if [ "$ALL_TESTS_PASSED" = false ]; then
  echo ""
  echo "⚠️  WARNING: Some MCP servers are not reachable"
  echo "   LibreChat will start, but MCP tools may not work"
  echo ""
  echo "   Troubleshooting:"
  echo "   1. Verify MCP server IP: $MCP_HOST"
  echo "   2. Check if MCP servers are running on ports 9001-9005"
  echo "   3. Verify Tailscale ACLs allow connections"
fi

# ============================================================
# STEP 7: Configure Proxy Environment
# ============================================================
echo ""
echo "▶ [7/8] Configuring proxy environment..."
SOCKS_PROXY="socks5://localhost:1055"
export ALL_PROXY="$SOCKS_PROXY"
export HTTP_PROXY="$SOCKS_PROXY"
export HTTPS_PROXY="$SOCKS_PROXY"
export PROXY="$SOCKS_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1,raw.githubusercontent.com,github.com,metadata.google.internal,169.254.169.254"

echo "   ✓ Proxy configured: $SOCKS_PROXY"

# ============================================================
# STEP 8: Infisical Authentication
# ============================================================
echo ""
echo "▶ [8/8] Authenticating with Infisical..."
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