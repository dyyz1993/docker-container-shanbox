#!/bin/bash
# manage-route.sh - Add/remove/list domain routes
# Usage:
#   ./manage-route.sh add <subdomain> <port> [policy]
#   ./manage-route.sh remove <subdomain>
#   ./manage-route.sh list

ROUTES_FILE="/etc/nginx/routes.d/default.conf"
NGINX_BIN="/usr/sbin/nginx"

list_routes() {
    echo "Current Routes:"
    echo "================"
    awk '/map \$host \$backend_port/,/^}/' "$ROUTES_FILE" | grep -E '~\^' | while read -r line; do
        prefix=$(echo "$line" | awk '{print $1}' | sed 's/~\^//;s/\\\.//;s/;.*//')
        port=$(echo "$line" | awk '{print $2}' | sed 's/;.*//')
        policy="public"
        awk '/map \$host \$access_policy/,/^}/' "$ROUTES_FILE" | grep -q "~\^${prefix}" && \
            policy=$(awk '/map \$host \$access_policy/,/^}/' "$ROUTES_FILE" | grep "~\^${prefix}" | awk '{print $2}' | sed 's/[";]//g')
        echo "  ${prefix}.example.com → port ${port} (${policy})"
    done
}

add_route() {
    local prefix="$1" port="$2" policy="${3:-public}"

    escaped_prefix=$(echo "$prefix" | sed 's/\./\\./g')

    if grep -q "~^${escaped_prefix}" "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} already exists"
        return 1
    fi

    sed -i "/map \$host \$backend_port/a\    ~^${escaped_prefix}\.              ${port};" "$ROUTES_FILE"
    sed -i "/map \$host \$access_policy/a\    ~^${escaped_prefix}\.              \"${policy}\";" "$ROUTES_FILE"

    ${NGINX_BIN} -t && ${NGINX_BIN} -s reload
    echo "Added: ${prefix}.example.com → port ${port} (${policy})"
}

remove_route() {
    local prefix="$1"
    escaped_prefix=$(echo "$prefix" | sed 's/\./\\./g')

    if ! grep -q "~^${escaped_prefix}" "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} not found"
        return 1
    fi

    sed -i "/~^${escaped_prefix}\./d" "$ROUTES_FILE"

    ${NGINX_BIN} -t && ${NGINX_BIN} -s reload
    echo "Removed: ${prefix}.example.com"
}

case "$1" in
    list)   list_routes ;;
    add)    add_route "$2" "$3" "$4" ;;
    remove) remove_route "$2" ;;
    *)
        echo "Usage: $0 {add|remove|list} [args]"
        echo "  add    <subdomain> <port> [policy]"
        echo "  remove <subdomain>"
        echo "  list"
        exit 1
        ;;
esac
