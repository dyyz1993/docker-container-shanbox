#!/bin/bash
set -e

if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

if [ -f /ssh/authorized_keys ]; then
    cp /ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N ''
fi

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''
fi

if [ -n "$PUBLIC_IP" ]; then
    export PUBLIC_IP
    if [ -f /etc/nginx/templates/server.conf.template ]; then
        envsubst '${PUBLIC_IP}' < /etc/nginx/templates/server.conf.template > /etc/nginx/conf.d/server.conf
    fi
else
    if [ -f /etc/nginx/templates/server.conf.template ]; then
        envsubst < /etc/nginx/templates/server.conf.template > /etc/nginx/conf.d/server.conf
    fi
fi

if [ -f /etc/nginx/custom/routes.conf ]; then
    cp /etc/nginx/custom/routes.conf /etc/nginx/conf.d/routes.conf
fi

mkdir -p /root/scripts /root/data /var/log/supervisor

nginx -t

exec "$@"
