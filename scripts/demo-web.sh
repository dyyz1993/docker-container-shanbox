#!/bin/bash
# demo-web.sh - Quick demo web server for testing
# Usage: ./demo-web.sh <port>

PORT="${1:-3001}"
echo "Starting demo web on port $PORT"

while true; do
  BODY="<!DOCTYPE html><html><head><title>Demo Web</title><style>body{font-family:sans-serif;padding:40px;background:#f5f5f5}h1{color:#333}p{color:#666}</style></head><body><h1>Demo Web Service</h1><p>Port: $PORT</p><p>Time: $(date)</p></body></html>"
  printf 'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: %d\r\n\r\n%s' \
    "${#BODY}" "$BODY" | nc -l -p "$PORT" -q 0 2>/dev/null
done
