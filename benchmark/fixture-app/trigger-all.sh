#!/usr/bin/env bash
# trigger-all.sh — Trigger all thread issues in the fixture app
# Run this after starting the app with: mvn spring-boot:run

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"

echo "Triggering all thread issues on $BASE_URL..."
echo ""

# Trigger the combined endpoint
echo ">>> POST /api/issues/trigger-all"
curl -s -X POST "$BASE_URL/api/issues/trigger-all" | python3 -m json.tool 2>/dev/null || true

echo ""
echo "All issues triggered. Wait 2-3 seconds, then capture a thread dump:"
echo ""
echo "  ./scripts/dump-collector.sh list"
echo "  ./scripts/dump-collector.sh capture <PID>"
echo ""
echo "Or use the skill:"
echo "  /thread-dump"
