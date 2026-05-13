#!/bin/bash
ROUTES_DATA="/etc/nginx/routes.d/routes.data"
ROUTES_CONF="/etc/nginx/routes.d/default.conf"
NGINX_BIN="/usr/sbin/nginx"

generate_key() {
    local key=""
    key=$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 8) || true
    if [ -z "$key" ]; then
        key=""
        local chars="abcdefghijklmnopqrstuvwxyz0123456789"
        for i in $(seq 1 8); do
            key="${key}${chars:$((RANDOM % 36)):1}"
        done
    fi
    echo "$key"
}

generate_subdomain() {
    local sub=""
    sub=$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6) || true
    if [ -z "$sub" ]; then
        sub=""
        local chars="abcdefghijklmnopqrstuvwxyz0123456789"
        for i in $(seq 1 6); do
            sub="${sub}${chars:$((RANDOM % 36)):1}"
        done
    fi
    echo "$sub"
}

regenerate_conf() {
    local tmp=$(mktemp)

    {
        echo "map \$host \$backend_port {"
        echo "    default              0;"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r sub host port policy key lan_only; do
                [ -z "$sub" ] && continue
                printf "    ~^%s\\.              %s;\n" "$sub" "$port"
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$backend_host {"
        echo "    default              \"\";"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r sub host port policy key lan_only; do
                [ -z "$sub" ] && continue
                if [ -n "$host" ]; then
                    printf "    ~^%s\\.              \"%s\";\n" "$sub" "$host"
                fi
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$access_policy {"
        echo "    default              \"public\";"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r sub host port policy key lan_only; do
                [ -z "$sub" ] && continue
                printf "    ~^%s\\.              \"%s\";\n" "$sub" "$policy"
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host\$arg_key \$key_valid {"
        echo "    default              0;"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r sub host port policy key lan_only; do
                [ -z "$sub" ] && continue
                if [ "$policy" = "key" ] && [ -n "$key" ]; then
                    printf "    \"~^%s\\..*%s$\"  1;\n" "$sub" "$key"
                fi
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$lan_only {"
        echo "    default              0;"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r sub host port policy key lan_only; do
                [ -z "$sub" ] && continue
                if [ "$lan_only" = "1" ]; then
                    printf "    ~^%s\\.              1;\n" "$sub"
                fi
            done < "$ROUTES_DATA"
        fi
        echo "}"
    } > "$tmp"

    mv "$tmp" "$ROUTES_CONF"
}

reload_nginx() {
    ${NGINX_BIN} -t 2>/dev/null && ${NGINX_BIN} -s reload 2>/dev/null
}

get_routes_raw() {
    [ ! -f "$ROUTES_DATA" ] && return 0
    while IFS='|' read -r sub host port policy key lan_only; do
        [ -z "$sub" ] && continue
        echo "${sub}|${host}|${port}|${policy}|${key}|${lan_only}"
    done < "$ROUTES_DATA"
}

list_pretty() {
    printf "%-15s %-15s %-8s %-10s %-12s %-8s\n" "SUBDOMAIN" "HOST" "PORT" "POLICY" "KEY" "LAN_ONLY"
    printf "%-15s %-15s %-8s %-10s %-12s %-8s\n" "---------------" "---------------" "--------" "----------" "------------" "--------"
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only; do
        [ -z "$host" ] && host="127.0.0.1"
        [ -z "$key" ] && key="-"
        printf "%-15s %-15s %-8s %-10s %-12s %-8s\n" "$sub" "$host" "$port" "$policy" "$key" "$lan_only"
    done
}

list_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only; do
        [ $first -eq 0 ] && printf ","
        first=0
        local h="${host:-127.0.0.1}"
        local k="${key:-}"
        local lo="${lan_only:-0}"
        printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","lan_only":%s}' "$sub" "$h" "$port" "$policy" "$k" "$lo"
    done
    printf "]"
}

status_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only; do
        local st="down"
        local check_host="${host:-127.0.0.1}"
        nc -z "$check_host" "$port" 2>/dev/null && st="up"
        [ $first -eq 0 ] && printf ","
        first=0
        local h="${host:-127.0.0.1}"
        local k="${key:-}"
        local lo="${lan_only:-0}"
        printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","lan_only":%s,"status":"%s"}' "$sub" "$h" "$port" "$policy" "$k" "$lo" "$st"
    done
    printf "]"
}

add_route() {
    local prefix="$1" port="$2" policy="${3:-public}" host="${4:-}"

    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port: $port (must be 1-65535)" >&2
        return 1
    fi

    case "$policy" in
        public|key|header|private) ;;
        *) echo "Invalid policy: $policy (must be public/key/header/private)" >&2; return 1 ;;
    esac

    if [ -f "$ROUTES_DATA" ] && grep -qE "^${prefix}\|" "$ROUTES_DATA" 2>/dev/null; then
        echo "Route ${prefix} already exists" >&2
        return 1
    fi

    local key=""
    if [ "$policy" = "key" ]; then
        key=$(generate_key)
    fi

    touch "$ROUTES_DATA"
    echo "${prefix}|${host}|${port}|${policy}|${key}|0" >> "$ROUTES_DATA"

    regenerate_conf
    reload_nginx
    echo "Added: ${prefix}.* → ${host:-127.0.0.1}:${port} (${policy})${key:+ key=}${key}"
}

register_route() {
    local address="$1" name="${2:-}" policy="${3:-key}"

    local host="" port=""
    if echo "$address" | grep -q ':'; then
        host=$(echo "$address" | cut -d: -f1)
        port=$(echo "$address" | cut -d: -f2)
    else
        port="$address"
    fi

    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port: $port (must be 1-65535)" >&2
        return 1
    fi

    case "$policy" in
        public|key|header|private) ;;
        *) echo "Invalid policy: $policy (must be public/key/header/private)" >&2; return 1 ;;
    esac

    local subdomain="$name"
    if [ -z "$subdomain" ]; then
        subdomain=$(generate_subdomain)
    fi

    if [ -f "$ROUTES_DATA" ] && grep -qE "^${subdomain}\|" "$ROUTES_DATA" 2>/dev/null; then
        echo "Route ${subdomain} already exists" >&2
        return 1
    fi

    local key=""
    if [ "$policy" = "key" ]; then
        key=$(generate_key)
    fi

    touch "$ROUTES_DATA"
    echo "${subdomain}|${host}|${port}|${policy}|${key}|1" >> "$ROUTES_DATA"

    regenerate_conf
    reload_nginx

    local domain="${DOMAIN:-shanbox.local}"
    local proto="https"
    local url_port=":8443"
    printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","url":"%s://%s.%s%s","lan_only":true}\n' \
        "$subdomain" "${host:-127.0.0.1}" "$port" "$policy" "$key" "$proto" "$subdomain" "$domain" "$url_port"
}

remove_route() {
    local prefix="$1"

    if [ ! -f "$ROUTES_DATA" ] || ! grep -qE "^${prefix}\|" "$ROUTES_DATA" 2>/dev/null; then
        echo "Route ${prefix} not found" >&2
        return 1
    fi

    grep -vE "^${prefix}\|" "$ROUTES_DATA" > "${ROUTES_DATA}.tmp"
    mv "${ROUTES_DATA}.tmp" "$ROUTES_DATA"

    regenerate_conf
    reload_nginx
    echo "Removed: ${prefix}.*"
}

case "$1" in
    list)        list_pretty ;;
    json)        list_json ;;
    status)      status_json ;;
    add)         add_route "$2" "$3" "$4" "$5" ;;
    register)    register_route "$2" "$3" "$4" ;;
    remove)      remove_route "$2" ;;
    _regenerate) regenerate_conf ;;
    *)
        echo "Usage: $0 {add|register|remove|list|json|status} [args]"
        echo "  add       <subdomain> <port> [policy] [host]  Add route manually"
        echo "  register  <address> [name] [policy]            Auto-register LAN service"
        echo "  remove    <subdomain>                          Remove route"
        echo "  list                                           List routes (table)"
        echo "  json                                           List routes (JSON)"
        echo "  status                                         List routes with health (JSON)"
        echo ""
        echo "Policies: public, key (default for register), header, private"
        echo "Address format: host:port (e.g. 192.168.0.4:3000) or just port (localhost)"
        exit 1
        ;;
esac
