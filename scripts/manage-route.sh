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
    awk '/^map \$host \$backend_port/,/^}/' "$ROUTES_FILE" | grep -E '^\s*~\^' | while read -r line; do
        prefix=$(echo "$line" | sed 's/.*~\^//;s/\\.*//;s/\..*//' | tr -d ' ')
        port=$(echo "$line" | awk '{print $2}' | sed 's/;.*//')
        policy="public"
        policy_line=$(awk '/^map \$host \$access_policy/,/^}/' "$ROUTES_FILE" | grep "~\^${prefix}" 2>/dev/null)
        if [ -n "$policy_line" ]; then
            policy=$(echo "$policy_line" | awk '{print $2}' | sed 's/[";]//g')
        fi
        echo "  ${prefix}.* → port ${port} (${policy})"
    done
}

add_route() {
    local prefix="$1" port="$2" policy="${3:-public}"

    if grep -q "~^${prefix}" "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} already exists"
        return 1
    fi

    local tmp=$(mktemp)
    awk -v p="$prefix" -v port="$port" -v pol="$policy" '
    /^map \$host \$backend_port/ { found_port=1 }
    found_port && /^}/ {
        printf "    ~^%s\\.              %s;\n", p, port
        found_port=0
    }
    /^map \$host \$access_policy/ { found_pol=1 }
    found_pol && /^}/ {
        printf "    ~^%s\\.              \"%s\";\n", p, pol
        found_pol=0
    }
    { print }
    ' "$ROUTES_FILE" > "$tmp"
    mv "$tmp" "$ROUTES_FILE"

    ${NGINX_BIN} -t && ${NGINX_BIN} -s reload
    echo "Added: ${prefix}.* → port ${port} (${policy})"
}

remove_route() {
    local prefix="$1"

    if ! grep -q "~^${prefix}" "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} not found"
        return 1
    fi

    grep -v "~^${prefix}" "$ROUTES_FILE" > "${ROUTES_FILE}.tmp"
    mv "${ROUTES_FILE}.tmp" "$ROUTES_FILE"

    ${NGINX_BIN} -t && ${NGINX_BIN} -s reload
    echo "Removed: ${prefix}.*"
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
        echo ""
        echo "Policies: public (default), key, header, private"
        exit 1
        ;;
esac
