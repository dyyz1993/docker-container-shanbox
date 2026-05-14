#!/bin/bash
ROUTES_DATA="/etc/nginx/routes.d/routes.data"
ROUTES_CONF="/etc/nginx/routes.d/default.conf"
NGINX_BIN="/usr/sbin/nginx"

now_epoch() {
    date +%s 2>/dev/null || echo "0"
}

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
            while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
                [ -z "$r_sub" ] && continue
                printf "    ~^%s\\.              %s;\n" "$r_sub" "$r_port"
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$backend_host {"
        echo "    default              \"\";"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
                [ -z "$r_sub" ] && continue
                if [ -n "$r_host" ]; then
                    printf "    ~^%s\\.              \"%s\";\n" "$r_sub" "$r_host"
                fi
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$access_policy {"
        echo "    default              \"public\";"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
                [ -z "$r_sub" ] && continue
                printf "    ~^%s\\.              \"%s\";\n" "$r_sub" "$r_policy"
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host\$arg_key \$key_valid {"
        echo "    default              0;"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
                [ -z "$r_sub" ] && continue
                if [ "$r_policy" = "key" ] && [ -n "$r_key" ]; then
                    printf "    \"~^%s\\..*%s$\"  1;\n" "$r_sub" "$r_key"
                fi
            done < "$ROUTES_DATA"
        fi
        echo "}"
        echo ""

        echo "map \$host \$lan_only {"
        echo "    default              0;"
        if [ -f "$ROUTES_DATA" ]; then
            while IFS='|' read -r r_sub r_host r_port r_policy r_key r_lan r_created; do
                [ -z "$r_sub" ] && continue
                if [ "$r_lan" = "1" ]; then
                    printf "    ~^%s\\.              1;\n" "$r_sub"
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
    while IFS='|' read -r sub host port policy key lan_only created_at rest; do
        [ -z "$sub" ] && continue
        echo "${sub}|${host}|${port}|${policy}|${key}|${lan_only}|${created_at:-0}"
    done < "$ROUTES_DATA"
}

list_pretty() {
    printf "%-15s %-18s %-8s %-10s %-12s %-8s %-12s\n" "SUBDOMAIN" "HOST" "PORT" "POLICY" "KEY" "LAN_ONLY" "CREATED"
    printf "%-15s %-18s %-8s %-10s %-12s %-8s %-12s\n" "---------------" "------------------" "--------" "----------" "------------" "--------" "------------"
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only created_at; do
        [ -z "$host" ] && host="127.0.0.1"
        [ -z "$key" ] && key="-"
        local ts="-"
        if [ -n "$created_at" ] && [ "$created_at" != "0" ]; then
            ts=$(date -d "@$created_at" '+%m-%d %H:%M' 2>/dev/null || echo "$created_at")
        fi
        printf "%-15s %-18s %-8s %-10s %-12s %-8s %-12s\n" "$sub" "$host" "$port" "$policy" "$key" "$lan_only" "$ts"
    done
}

list_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only created_at; do
        [ $first -eq 0 ] && printf ","
        first=0
        local h="${host:-127.0.0.1}"
        local k="${key:-}"
        local lo="${lan_only:-0}"
        local ca="${created_at:-0}"
        printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","lan_only":%s,"created_at":%s}' "$sub" "$h" "$port" "$policy" "$k" "$lo" "$ca"
    done
    printf "]"
}

status_json() {
    local first=1
    printf "["
    get_routes_raw | while IFS='|' read -r sub host port policy key lan_only created_at; do
        local st="down"
        local check_host="${host:-127.0.0.1}"
        nc -z "$check_host" "$port" 2>/dev/null && st="up"
        [ $first -eq 0 ] && printf ","
        first=0
        local h="${host:-127.0.0.1}"
        local k="${key:-}"
        local lo="${lan_only:-0}"
        local ca="${created_at:-0}"
        printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","lan_only":%s,"created_at":%s,"status":"%s"}' "$sub" "$h" "$port" "$policy" "$k" "$lo" "$ca" "$st"
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

    local created=$(now_epoch)

    touch "$ROUTES_DATA"
    echo "${prefix}|${host}|${port}|${policy}|${key}|0|${created}" >> "$ROUTES_DATA"

    regenerate_conf
    reload_nginx
    echo "Added: ${prefix}.* -> ${host:-127.0.0.1}:${port} (${policy})${key:+ key=}${key}"
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

    if echo "$host" | grep -qiE '^127\.' || [ "$host" = "localhost" ]; then
        CLIENT_IP=$(echo "$SSH_CONNECTION" | awk '{print $1}')
        if [ -n "$CLIENT_IP" ]; then
            host="$CLIENT_IP"
        else
            echo "Warning: 127.0.0.1/localhost inside container points to itself. Specify the real LAN IP or use the API (auto-detects caller IP)." >&2
            return 1
        fi
    fi

    if ! echo "$port" | grep -qE '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "Invalid port: $port (must be 1-65535)" >&2
        return 1
    fi

    case "$policy" in
        public|key|header|private) ;;
        *) echo "Invalid policy: $policy (must be public/key/header/private)" >&2; return 1 ;;
    esac

    local existing_sub="" existing_policy="" existing_key="" existing_lan="" existing_created=""
    if [ -f "$ROUTES_DATA" ] && [ -n "$host" ]; then
        while IFS='|' read -r e_sub e_host e_port e_policy e_key e_lan e_created; do
            [ -z "$e_sub" ] && continue
            if [ "$e_host" = "$host" ] && [ "$e_port" = "$port" ]; then
                existing_sub="$e_sub"
                existing_policy="$e_policy"
                existing_key="$e_key"
                existing_lan="${e_lan:-0}"
                existing_created="${e_created:-$(now_epoch)}"
                break
            fi
        done < "$ROUTES_DATA"
    fi

    if [ -n "$existing_sub" ]; then
        local domain="${DOMAIN:-shanbox.local}"
        local proto="https"
        local url_port=":8443"

        if [ "$policy" != "$existing_policy" ]; then
            local new_key="$existing_key"
            if [ "$policy" = "key" ] && [ -z "$existing_key" ]; then
                new_key=$(generate_key)
            fi
            if [ "$policy" != "key" ]; then
                new_key=""
            fi
            grep -vE "^${existing_sub}\|" "$ROUTES_DATA" > "${ROUTES_DATA}.tmp"
            echo "${existing_sub}|${host}|${port}|${policy}|${new_key}|${existing_lan}|${existing_created}" >> "${ROUTES_DATA}.tmp"
            mv "${ROUTES_DATA}.tmp" "$ROUTES_DATA"
            regenerate_conf
            reload_nginx
            printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","url":"%s://%s.%s%s","lan_only":false,"duplicated":true,"updated":true,"created_at":%s}\n' \
                "$existing_sub" "${host:-127.0.0.1}" "$port" "$policy" "$new_key" "$proto" "$existing_sub" "$domain" "$url_port" "$existing_created"
        else
            printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","url":"%s://%s.%s%s","lan_only":false,"duplicated":true,"updated":false,"created_at":%s}\n' \
                "$existing_sub" "${host:-127.0.0.1}" "$port" "$existing_policy" "$existing_key" "$proto" "$existing_sub" "$domain" "$url_port" "$existing_created"
        fi
        return 0
    fi

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

    local created=$(now_epoch)

    touch "$ROUTES_DATA"
    echo "${subdomain}|${host}|${port}|${policy}|${key}|0|${created}" >> "$ROUTES_DATA"

    regenerate_conf
    reload_nginx

    local domain="${DOMAIN:-shanbox.local}"
    local proto="https"
    local url_port=":8443"
    printf '{"subdomain":"%s","host":"%s","port":%s,"policy":"%s","key":"%s","url":"%s://%s.%s%s","lan_only":false,"duplicated":false,"created_at":%s}\n' \
        "$subdomain" "${host:-127.0.0.1}" "$port" "$policy" "$key" "$proto" "$subdomain" "$domain" "$url_port" "$created"
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

prune_routes() {
    local max_age="$1"
    if ! echo "$max_age" | grep -qE '^[0-9]+$' || [ "$max_age" -lt 1 ]; then
        echo "Usage: $0 prune <max_age_seconds>" >&2
        echo "  Removes routes older than max_age_seconds" >&2
        return 1
    fi

    local now=$(now_epoch)
    local cutoff=$((now - max_age))
    local removed=0

    [ ! -f "$ROUTES_DATA" ] && echo "No routes to prune" && return 0

    local tmp=$(mktemp)
    while IFS='|' read -r sub host port policy key lan_only created_at rest; do
        [ -z "$sub" ] && continue
        local ca="${created_at:-0}"
        if [ "$ca" -ge "$cutoff" ] 2>/dev/null; then
            echo "${sub}|${host}|${port}|${policy}|${key}|${lan_only}|${ca}" >> "$tmp"
        else
            echo "Pruning: $sub (${host}:${port}) age=$((now - ca))s" >&2
            removed=$((removed + 1))
        fi
    done < "$ROUTES_DATA"

    mv "$tmp" "$ROUTES_DATA"

    if [ "$removed" -gt 0 ]; then
        regenerate_conf
        reload_nginx
    fi
    echo "Pruned ${removed} route(s)"
}

case "$1" in
    list)        list_pretty ;;
    json)        list_json ;;
    status)      status_json ;;
    add)         add_route "$2" "$3" "$4" "$5" ;;
    register)    register_route "$2" "$3" "$4" ;;
    remove)      remove_route "$2" ;;
    prune)       prune_routes "$2" ;;
    _regenerate) regenerate_conf ;;
    *)
        echo "Usage: $0 {add|register|remove|list|json|status|prune} [args]"
        echo "  add       <subdomain> <port> [policy] [host]  Add route manually"
        echo "  register  <address> [name] [policy]            Auto-register LAN service"
        echo "  remove    <subdomain>                          Remove route"
        echo "  prune     <max_age_seconds>                    Remove routes older than N seconds"
        echo "  list                                           List routes (table)"
        echo "  json                                           List routes (JSON)"
        echo "  status                                         List routes with health (JSON)"
        echo ""
        echo "Policies: public, key (default for register), header, private"
        echo "Address format: host:port (e.g. 192.168.0.4:3000) or just port (localhost)"
        exit 1
        ;;
esac