#!/bin/bash
# demo-api.sh - Quick demo API server for testing
# Usage: ./demo-api.sh <port>

PORT="${1:-3000}"
echo "Starting demo API on port $PORT"
RESP='{"service":"demo-api","port":'"$PORT"',"time":"'"$(date -Iseconds)"'","headers":{}}'

while true; do
  printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s' \
    "${#RESP}" "$RESP" | nc -l -p "$PORT" -q 0 2>/dev/null
done
