#!/bin/bash
set -e

# ==========================================
# 1. SSH Key injection
# ==========================================
if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
if [ -f /ssh/authorized_keys ]; then
    cp /ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' -q
fi
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -q
fi

# ==========================================
# 2. Peer IP detection (PUBLIC_IP)
# ==========================================
if [ -n "$PUBLIC_IP" ]; then
    cat > /etc/nginx/conf.d/geo_peer.conf << NGINXEOF
geo \$is_peer {
    default 0;
    ${PUBLIC_IP} 1;
}
NGINXEOF
else
    cat > /etc/nginx/conf.d/geo_peer.conf << NGINXEOF
geo \$is_peer {
    default 0;
}
NGINXEOF
fi

# ==========================================
# 3. Nginx config generation
# ==========================================
envsubst '${PUBLIC_IP} ${DOMAIN}' \
    < /etc/nginx/templates/server.conf.template \
    > /etc/nginx/conf.d/server.conf

# ==========================================
# 4. Routes config
# ==========================================
if [ -f /etc/nginx/routes.d/routes.data ] && [ -s /etc/nginx/routes.d/routes.data ]; then
    bash /root/scripts/manage-route.sh _regenerate
elif [ ! -f /etc/nginx/routes.d/default.conf ]; then
    touch /etc/nginx/routes.d/routes.data
    bash /root/scripts/manage-route.sh _regenerate
fi

# ==========================================
# 5. Ensure dirs
# ==========================================
mkdir -p /root/scripts /root/data /var/log/supervisor

# ==========================================
# 6. Generate MOTD
# ==========================================
DOMAIN="${DOMAIN:-shanbox.19930810.xyz}"
ROUTES_DATA="/etc/nginx/routes.d/routes.data"
ROUTE_COUNT=0
if [ -f "$ROUTES_DATA" ]; then
    ROUTE_COUNT=$(grep -c '.' "$ROUTES_DATA" 2>/dev/null || echo 0)
fi

cat > /etc/motd << MOTDEOF

  _____ _   _ _   _ _____ ____  ___  ___  ___  
 / ____| \ | | | | / / ___|  _ \|_  |/ _ \/ _ \ 
| (___ |  \| | | \| \ \`--.| |_) | | | | | | | |
 \___ \|     | | . \` |--. \\  _ <| | | | | | | |
 ____) | |\  | | |\  /\__/ / |_) | |/ /\ |_| |_| 
|_____/|_| \_|_|_| \_\____/|____/|___/ \___/ (_) 

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Shanbox — LAN Service Reverse Proxy
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Paths:
    Routes data   /etc/nginx/routes.d/routes.data
    Routes config /etc/nginx/routes.d/default.conf
    Scripts       /root/scripts/
    Data          /root/data/
    Logs          /var/log/nginx/

  ┌─────────────────────────────────────────────┐
  │  CLI Usage                                  │
  └─────────────────────────────────────────────┘

  register - auto-register a LAN service
    /root/scripts/manage-route.sh register <host:port> [name] [policy]

    Examples:
      /root/scripts/manage-route.sh register 192.168.0.4:3000
      /root/scripts/manage-route.sh register 192.168.0.4:5173 myapp public
      /root/scripts/manage-route.sh register 3000              # auto-detect caller IP

    Behavior:
      - Same host:port already exists  -> return existing route (no duplicate)
      - Policy changed                 -> update existing route
      - New host:port                  -> create new route with random subdomain
      - name provided                  -> use as subdomain instead of random

  add - manually add route by subdomain
    /root/scripts/manage-route.sh add <subdomain> <port> [policy] [host]

    Examples:
      /root/scripts/manage-route.sh add myapp 3000 public
      /root/scripts/manage-route.sh add api 8080 key 192.168.0.5

  remove - delete a route
    /root/scripts/manage-route.sh remove <subdomain>

  list / status - view routes
    /root/scripts/manage-route.sh list       # table format
    /root/scripts/manage-route.sh status     # with backend health check

  prune - remove old routes
    /root/scripts/manage-route.sh prune <seconds>

    Examples:
      /root/scripts/manage-route.sh prune 86400    # remove routes older than 1 day
      /root/scripts/manage-route.sh prune 3600     # remove routes older than 1 hour

  ┌─────────────────────────────────────────────┐
  │  API (LAN only: /__api__/)                  │
  └─────────────────────────────────────────────┘

  POST /__api__/register  - register a service
    curl -X POST http://shanbox/__api__/register \\
      -H "Content-Type: application/json" \\
      -d '{"address":"192.168.0.4:3000","policy":"public"}'
    curl -X POST http://shanbox/__api__/register \\
      -d '{"address":"192.168.0.4:5173","name":"myapp","policy":"public"}'
    curl -X POST http://shanbox/__api__/register \\
      -d '{"port":3000,"policy":"key"}'            # auto-detect caller IP

    Response (new):
      201 {"subdomain":"abc123","url":"https://abc123.${DOMAIN}:8443",...}
    Response (duplicate):
      200 {"subdomain":"abc123","duplicated":true,"updated":false,...}
    Response (policy changed):
      200 {"subdomain":"abc123","duplicated":true,"updated":true,...}

  POST /__api__/routes    - add route manually
    curl -X POST http://shanbox/__api__/routes \\
      -d '{"subdomain":"myapp","port":3000,"policy":"public"}'

  GET  /__api__/routes    - list all routes (JSON)
  GET  /__api__/routes/status - list with backend health

  DELETE /__api__/routes/<subdomain> - remove route
    curl -X DELETE http://shanbox/__api__/routes/myapp

  ┌─────────────────────────────────────────────┐
  │  Access Policies                            │
  └─────────────────────────────────────────────┘

    public   - no authentication required
    key      - requires ?key=xxx URL parameter
    header   - requires X-Auth-Token header
    private  - only LAN/whitelist IPs can access

    Default policy for register: key
    Auth bypass: LAN IPs (10.x, 192.168.x, 127.x) and PUBLIC_IP always skip auth

  ┌─────────────────────────────────────────────┐
  │  Features                                   │
  └─────────────────────────────────────────────┘

    CORS:       enabled globally (Access-Control-Allow-Origin: *)
    WebSocket:  supported (Upgrade/Connection proxy, 24h timeout)
    Dedup:      same host:port reuses existing subdomain
    Auto-detect:127.0.0.1/localhost in address -> replaced with caller IP
    Health:     manage-route.sh status checks if backend port is listening

  Domain: *.${DOMAIN}
MOTDEOF

if [ -f "$ROUTES_DATA" ] && [ -s "$ROUTES_DATA" ]; then
    echo "" >> /etc/motd
    echo "  Active Routes:" >> /etc/motd
    echo "  ─────────────────────────────────────────────────" >> /etc/motd
    printf "  %-12s %-20s %-8s %-8s %-10s %s\n" "SUBDOMAIN" "UPSTREAM" "PORT" "POLICY" "KEY" "CREATED" >> /etc/motd
    while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
        [ -z "$r_sub" ] && continue
        r_key_display="${r_key:-(none)}"
        [ ${#r_key_display} -gt 8 ] && r_key_display="${r_key_display:0:8}..."
        r_ts=""
        if [ -n "$r_created" ] && [ "$r_created" != "0" ]; then
            r_ts=$(date -d "@$r_created" '+%m-%d %H:%M' 2>/dev/null || echo "")
        fi
        printf "  %-12s %-20s %-8s %-8s %-10s %s\n" "$r_sub" "${r_host:-127.0.0.1}" "$r_port" "$r_policy" "$r_key_display" "$r_ts" >> /etc/motd
    done < "$ROUTES_DATA"
    echo "  ─────────────────────────────────────────────────" >> /etc/motd
    echo "  Total: ${ROUTE_COUNT} routes" >> /etc/motd
fi

echo "" >> /etc/motd

# ==========================================
# 7. Validate & Start
# ==========================================
echo "[entrypoint] Checking Nginx config..."
nginx -t

echo "[entrypoint] Starting supervisor..."
exec "$@"
