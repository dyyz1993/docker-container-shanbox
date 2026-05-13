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
# 6. Validate & Start
# ==========================================
echo "[entrypoint] Checking Nginx config..."
nginx -t

echo "[entrypoint] Starting supervisor..."
exec "$@"
