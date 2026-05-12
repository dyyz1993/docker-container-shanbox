#!/bin/bash
docker compose down 2>/dev/null
docker compose up -d --build
sleep 3
docker compose ps
docker compose exec server supervisorctl status
echo ""
echo "Ready. SSH: ssh root@localhost -p 2222"
echo "Routes: docker compose exec server ./scripts/manage-route.sh list"
