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
    Logs          /var/log/

  CLI Usage:
    manage-route.sh register <host:port> [name] [policy]
    manage-route.sh add <subdomain> <port> [policy] [host]
    manage-route.sh remove <subdomain>
    manage-route.sh list

  API (LAN only):
    POST   /__api__/register   {"address":"192.168.0.4:3000"}
    GET    /__api__/routes
    DELETE /__api__/routes/<subdomain>

  Policies: public | key | header | private

  Current routes: ${ROUTE_COUNT}
  Domain: *.${DOMAIN}
MOTDEOF

# ==========================================
# 7. Validate & Start
# ==========================================
echo "[entrypoint] Checking Nginx config..."
nginx -t

echo "[entrypoint] Starting supervisor..."
exec "$@"
