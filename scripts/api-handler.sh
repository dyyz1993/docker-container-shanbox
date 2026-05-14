#!/bin/bash
ROUTES_SCRIPT="/root/scripts/manage-route.sh"

respond() {
    local code=$1 ct=$2 body=$3
    printf "HTTP/1.1 %s\r\nContent-Type: %s\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" "$code" "$ct" "${#body}" "$body"
}

read -r REQUEST_LINE
METHOD=$(echo "$REQUEST_LINE" | awk '{print $1}')
PATH_PART=$(echo "$REQUEST_LINE" | awk '{print $2}')

CONTENT_LENGTH=0
CALLER_IP=""
while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r')
    [ -z "$line" ] && break
    if echo "$line" | grep -qi "^Content-Length:"; then
        CONTENT_LENGTH=$(echo "$line" | awk '{print $2}')
    fi
    if echo "$line" | grep -qi "^X-Real-IP:"; then
        CALLER_IP=$(echo "$line" | awk '{print $2}' | xargs)
    fi
    if echo "$line" | grep -qi "^X-Forwarded-For:"; then
        FIRST_IP=$(echo "$line" | awk '{print $2}' | cut -d, -f1 | xargs)
        [ -z "$CALLER_IP" ] && CALLER_IP="$FIRST_IP"
    fi
done

BODY=""
if [ "$METHOD" = "POST" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
    BODY=$(dd bs=1 count=$CONTENT_LENGTH 2>/dev/null)
fi

if [ "$METHOD" = "OPTIONS" ]; then
    respond "200 OK" "text/plain" ""
    exit 0
fi

case "$METHOD" in
    GET)
        case "$PATH_PART" in
            /api/routes/status)
                RESULT=$($ROUTES_SCRIPT status 2>/dev/null || echo '[]')
                respond "200 OK" "application/json" "$RESULT"
                ;;
            /api/routes)
                RESULT=$($ROUTES_SCRIPT json 2>/dev/null || echo '[]')
                respond "200 OK" "application/json" "$RESULT"
                ;;
            *)
                respond "404 Not Found" "application/json" '{"error":"not found"}'
                ;;
        esac
        ;;
    POST)
        case "$PATH_PART" in
            /api/register)
                ADDRESS=$(echo "$BODY" | sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                NAME=$(echo "$BODY" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                POLICY=$(echo "$BODY" | sed -n 's/.*"policy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                PORT_ONLY=$(echo "$BODY" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

                if [ -z "$ADDRESS" ] && [ -n "$PORT_ONLY" ]; then
                    ADDRESS="$PORT_ONLY"
                fi

                ADDR_HOST=""
                ADDR_PORT=""
                if echo "$ADDRESS" | grep -q ':'; then
                    ADDR_HOST=$(echo "$ADDRESS" | cut -d: -f1)
                    ADDR_PORT=$(echo "$ADDRESS" | cut -d: -f2)
                else
                    ADDR_PORT="$ADDRESS"
                fi

                if echo "$ADDR_HOST" | grep -qiE '^127\.' || [ "$ADDR_HOST" = "localhost" ] || [ -z "$ADDR_HOST" ]; then
                    if [ -n "$CALLER_IP" ]; then
                        ADDRESS="${CALLER_IP}:${ADDR_PORT}"
                    else
                        respond "400 Bad Request" "application/json" '{"error":"cannot detect caller IP, specify address explicitly (e.g. 192.168.0.4:3000)"}'
                        exit 0
                    fi
                fi

                OUTPUT=$($ROUTES_SCRIPT register "$ADDRESS" "$NAME" "$POLICY" 2>&1)
                EXIT_CODE=$?
                if [ $EXIT_CODE -eq 0 ]; then
                    if echo "$OUTPUT" | grep -q '"duplicated":true'; then
                        respond "200 OK" "application/json" "$OUTPUT"
                    else
                        respond "201 Created" "application/json" "$OUTPUT"
                    fi
                else
                    respond "409 Conflict" "application/json" "{\"error\":\"$OUTPUT\"}"
                fi
                ;;
            /api/routes)
                SUBDOMAIN=$(echo "$BODY" | sed -n 's/.*"subdomain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                PORT=$(echo "$BODY" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
                POLICY=$(echo "$BODY" | sed -n 's/.*"policy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                HOST=$(echo "$BODY" | sed -n 's/.*"host"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                [ -z "$POLICY" ] && POLICY="public"

                if [ -z "$SUBDOMAIN" ] || [ -z "$PORT" ]; then
                    respond "400 Bad Request" "application/json" '{"error":"subdomain and port are required"}'
                    exit 0
                fi

                OUTPUT=$($ROUTES_SCRIPT add "$SUBDOMAIN" "$PORT" "$POLICY" "$HOST" 2>&1)
                EXIT_CODE=$?
                if [ $EXIT_CODE -eq 0 ]; then
                    respond "201 Created" "application/json" "{\"message\":\"route added\",\"subdomain\":\"$SUBDOMAIN\",\"port\":$PORT,\"policy\":\"$POLICY\"}"
                else
                    respond "409 Conflict" "application/json" "{\"error\":\"$OUTPUT\"}"
                fi
                ;;
            *)
                respond "404 Not Found" "application/json" '{"error":"not found"}'
                ;;
        esac
        ;;
    DELETE)
        case "$PATH_PART" in
            /api/routes/*)
                SUBDOMAIN=$(echo "$PATH_PART" | sed 's|/api/routes/||')
                OUTPUT=$($ROUTES_SCRIPT remove "$SUBDOMAIN" 2>&1)
                EXIT_CODE=$?
                if [ $EXIT_CODE -eq 0 ]; then
                    respond "200 OK" "application/json" "{\"message\":\"route removed\",\"subdomain\":\"$SUBDOMAIN\"}"
                else
                    respond "404 Not Found" "application/json" "{\"error\":\"$OUTPUT\"}"
                fi
                ;;
            *)
                respond "404 Not Found" "application/json" '{"error":"not found"}'
                ;;
        esac
        ;;
    *)
        respond "405 Method Not Allowed" "application/json" '{"error":"method not allowed"}'
        ;;
esac
