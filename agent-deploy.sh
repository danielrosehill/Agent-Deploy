#!/usr/bin/env bash
# Agent-friendly deploy wrapper
# Provides minimal status output suitable for AI agent context
# Full logs written to /tmp/deploy.log
#
# Usage: ./agent-deploy.sh [quick]
#
# Why use this?
# When working with AI coding assistants (Claude, Copilot, etc.), verbose
# deployment output consumes context tokens unnecessarily. This script
# outputs only key milestones while logging full details for debugging.
#
# Configuration:
#   Set these environment variables or edit the defaults below:
#   - VM_HOST: Remote VM IP/hostname
#   - VM_PORT: Application port
#   - REMOTE_DIR: Deployment directory on remote

set -e

cd "$(dirname "$0")"

LOG_FILE="/tmp/deploy.log"
: > "$LOG_FILE"  # Clear log file

# Configuration - customize these
REPO_DIR="$(pwd)"
if [ -f "$REPO_DIR/.env.production" ]; then
    source "$REPO_DIR/.env.production"
fi

VM_HOST="${VM_HOST:-YOUR_VM_IP}"
VM_PORT="${VM_PORT:-3000}"
REMOTE_DIR="${REMOTE_DIR:-/home/deploy/app}"
IMAGE_NAME="${IMAGE_NAME:-myapp:latest}"
DB_CONTAINER="${DB_CONTAINER:-app-db}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-appdb}"
MIGRATIONS_DIR="$REPO_DIR/migrations"

# Helper to run command silently, show output only on error
run_quiet() {
    local desc="$1"
    shift
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        echo "FAILED: $desc"
        echo "Last 20 lines of log:"
        tail -20 "$LOG_FILE"
        exit 1
    fi
}

# Quick restart mode
if [[ "$1" == "quick" ]]; then
    echo "Deployment started (quick restart)"
    run_quiet "Restart container" ssh "$VM_HOST" "docker restart app"
    echo "Deployment complete"
    ssh "$VM_HOST" "curl -s http://localhost:$VM_PORT/health" 2>/dev/null && echo "Status: OK" || echo "Status: Starting..."
    exit 0
fi

echo "Deployment started"

# Step 0: Git commit/push
echo "Committing to GitHub..."
if [ -n "$(git status --porcelain)" ]; then
    git add -A >> "$LOG_FILE" 2>&1
    git commit -m "deploy: $(date +%Y-%m-%d_%H:%M)" >> "$LOG_FILE" 2>&1
    git push >> "$LOG_FILE" 2>&1
else
    git push >> "$LOG_FILE" 2>&1 || true
fi

# Step 1: Build
echo "Building image..."
run_quiet "Docker build" docker build -t "$IMAGE_NAME" \
    --build-arg COMMIT=$(git rev-parse --short HEAD) \
    --build-arg BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    -f Dockerfile .

# Step 2: Transfer image
echo "Transferring to VM..."
run_quiet "Image transfer" bash -c "docker save $IMAGE_NAME | ssh $VM_HOST 'docker load'"

# Step 3: Transfer config
run_quiet "Config transfer" bash -c "ssh $VM_HOST 'mkdir -p $REMOTE_DIR' && scp docker-compose.yml ${VM_HOST}:${REMOTE_DIR}/ && [ -f .env.production ] && scp .env.production ${VM_HOST}:${REMOTE_DIR}/.env || true"

# Step 4: Migrations
PENDING_MIGRATIONS=$(ls -1 "$MIGRATIONS_DIR/"*.sql 2>/dev/null | wc -l)
if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
    echo "Running $PENDING_MIGRATIONS migration(s)..."
    ssh "$VM_HOST" "mkdir -p $REMOTE_DIR/migrations" >> "$LOG_FILE" 2>&1
    scp "$MIGRATIONS_DIR/"*.sql "${VM_HOST}:${REMOTE_DIR}/migrations/" >> "$LOG_FILE" 2>&1
fi

# Step 5: Restart containers
echo "Restarting containers..."
ssh "$VM_HOST" << REMOTE_SCRIPT >> "$LOG_FILE" 2>&1
set -e
cd $REMOTE_DIR
docker compose down 2>/dev/null || true
docker compose up -d
sleep 10

if [ -d "migrations" ] && [ "\$(ls -A migrations/*.sql 2>/dev/null)" ]; then
    for migration in migrations/*.sql; do
        if [ -f "\$migration" ]; then
            docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME < "\$migration" 2>&1 || true
        fi
    done
    rm -rf migrations/*.sql
fi

sleep 5
docker image prune -f
REMOTE_SCRIPT

# Step 6: Archive migrations
if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
    mkdir -p "$MIGRATIONS_DIR/applied"
    mv "$MIGRATIONS_DIR/"*.sql "$MIGRATIONS_DIR/applied/" 2>/dev/null || true
    if [ -n "$(git status --porcelain "$MIGRATIONS_DIR")" ]; then
        git add "$MIGRATIONS_DIR/" >> "$LOG_FILE" 2>&1
        git commit -m "chore: archive applied migrations" >> "$LOG_FILE" 2>&1
        git push >> "$LOG_FILE" 2>&1
    fi
fi

# Health check
echo "Deployment complete"
if ssh "$VM_HOST" "curl -s http://localhost:$VM_PORT/health" 2>/dev/null | grep -q "ok\|true\|healthy"; then
    echo "Status: OK - http://${VM_HOST}:${VM_PORT}"
else
    echo "Status: Starting - http://${VM_HOST}:${VM_PORT}"
fi
