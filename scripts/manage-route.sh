#!/bin/bash
ROUTES_FILE="/etc/nginx/routes.d/default.conf"
NGINX_BIN="/usr/sbin/nginx"

get_routes_raw() {
    awk '/^map \$host \$backend_port/,/^}/' "$ROUTES_FILE" | grep -E '^\s*~\^' | while read -r line; do
        subdomain=$(echo "$line" | sed 's/.*~\^//;s/\\\.//;s/\..*//;s/;.*//' | tr -d ' ')
        port=$(echo "$line" | awk '{print $2}' | sed 's/;.*//')
        policy_line=$(awk '/^map \$host \$access_policy/,/^}/' "$ROUTES_FILE" | grep -F "~^${subdomain}")
        policy="public"
        if [ -n "$policy_line" ]; then
            policy=$(echo "$policy_line" | awk '{print $2}' | sed 's/[";]//g')
        fi
        echo "${subdomain}|${port}|${policy}"
    done
}

list_pretty() {
    printf "%-20s %-10s %-10s\n" "SUBDOMAIN" "PORT" "POLICY"
    printf "%-20s %-10s %-10s\n" "--------------------" "----------" "----------"
    get_routes_raw | while IFS='|' read -r sub port policy; do
        printf "%-20s %-10s %-10s\n" "$sub" "$port" "$policy"
    done
}

list_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub port policy; do
        [ $first -eq 0 ] && printf ","
        first=0
        printf '{"subdomain":"%s","port":%s,"policy":"%s"}' "$sub" "$port" "$policy"
    done
    printf "]"
}

status_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub port policy; do
        local st="down"
        nc -z localhost "$port" 2>/dev/null && st="up"
        [ $first -eq 0 ] && printf ","
        first=0
        printf '{"subdomain":"%s","port":%s,"policy":"%s","status":"%s"}' "$sub" "$port" "$policy" "$st"
    done
    printf "]"
}

add_route() {
    local prefix="$1" port="$2" policy="${3:-public}"

    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port: $port (must be 1-65535)" >&2
        return 1
    fi

    case "$policy" in
        public|key|header|private) ;;
        *) echo "Invalid policy: $policy (must be public/key/header/private)" >&2; return 1 ;;
    esac

    if grep -qE "^\s*~\^${prefix}\\\." "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} already exists" >&2
        return 1
    fi

    local tmp=$(mktemp)
    awk -v p="$prefix" -v port="$port" '
    /^map \$host \$backend_port/ { found_port=1 }
    found_port && /^}/ {
        printf "    ~^%s\\.              %s;\n", p, port
        found_port=0
    }
    { print }
    ' "$ROUTES_FILE" > "${tmp}.1"

    awk -v p="$prefix" -v pol="$policy" '
    /^map \$host \$access_policy/ { found_pol=1 }
    found_pol && /^}/ {
        printf "    ~^%s\\.              \"%s\";\n", p, pol
        found_pol=0
    }
    { print }
    ' "${tmp}.1" > "${tmp}.2"

    mv "${tmp}.2" "$ROUTES_FILE"
    rm -f "${tmp}.1"

    ${NGINX_BIN} -t 2>/dev/null && ${NGINX_BIN} -s reload 2>/dev/null
    echo "Added: ${prefix}.* → port ${port} (${policy})"
}

remove_route() {
    local prefix="$1"

    if ! grep -qE "^\s*~\^${prefix}\\\." "$ROUTES_FILE" 2>/dev/null; then
        echo "Route ${prefix} not found" >&2
        return 1
    fi

    grep -vE "^\s*~\^${prefix}\\\." "$ROUTES_FILE" > "${ROUTES_FILE}.tmp"
    mv "${ROUTES_FILE}.tmp" "$ROUTES_FILE"

    ${NGINX_BIN} -t 2>/dev/null && ${NGINX_BIN} -s reload 2>/dev/null
    echo "Removed: ${prefix}.*"
}

case "$1" in
    list)     list_pretty ;;
    json)     list_json ;;
    status)   status_json ;;
    add)      add_route "$2" "$3" "$4" ;;
    remove)   remove_route "$2" ;;
    *)
        echo "Usage: $0 {add|remove|list|json|status} [args]"
        echo "  add    <subdomain> <port> [policy]  Add route"
        echo "  remove <subdomain>                   Remove route"
        echo "  list                                 List routes (table)"
        echo "  json                                 List routes (JSON)"
        echo "  status                               List routes with health (JSON)"
        echo ""
        echo "Policies: public (default), key, header, private"
        exit 1
        ;;
esac
