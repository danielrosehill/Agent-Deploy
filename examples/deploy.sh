#!/bin/bash
# Deploy application to remote VM
# Builds image locally, transfers to remote, runs docker-compose
#
# Usage: ./deploy.sh [quick]
#
# Configuration:
#   Set these environment variables or edit the defaults below:
#   - VM_HOST: Remote VM IP/hostname
#   - VM_PORT: Application port
#   - REMOTE_DIR: Deployment directory on remote

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$REPO_DIR/migrations"

# Load production environment if available
if [ -f "$REPO_DIR/.env.production" ]; then
    source "$REPO_DIR/.env.production"
fi

# Configuration - customize these
VM_HOST="${VM_HOST:-YOUR_VM_IP}"
VM_PORT="${VM_PORT:-3000}"
REMOTE_DIR="${REMOTE_DIR:-/home/deploy/app}"
IMAGE_NAME="${IMAGE_NAME:-myapp:latest}"
DB_CONTAINER="${DB_CONTAINER:-app-db}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-appdb}"

# Quick restart mode
if [[ "$1" == "quick" ]]; then
    echo "Quick deploy - restarting container only..."
    ssh "$VM_HOST" "docker restart app && docker logs -f --tail 20 app"
    exit 0
fi

echo "=== Deploy Pipeline ==="
echo "Deploying to $VM_HOST:$VM_PORT"
echo ""

# Step 0: Commit and push to GitHub
echo "[0/5] Committing to GitHub..."
cd "$REPO_DIR"
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "deploy: $(date +%Y-%m-%d_%H:%M)"
    git push
    echo "Changes pushed."
else
    git push 2>/dev/null || echo "Already up to date."
fi
echo ""

# Step 1: Build images
echo "[1/5] Building images..."
docker build -t "$IMAGE_NAME" \
    --build-arg COMMIT=$(git rev-parse --short HEAD) \
    --build-arg BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    -f Dockerfile \
    .

# Step 2: Save and transfer images
echo "[2/5] Transferring images to VM..."
docker save "$IMAGE_NAME" | ssh "$VM_HOST" "docker load"

# Step 3: Transfer config files
echo "[3/5] Transferring config..."
ssh "$VM_HOST" "mkdir -p $REMOTE_DIR"
scp "$REPO_DIR/docker-compose.yml" "${VM_HOST}:${REMOTE_DIR}/"
[ -f "$REPO_DIR/.env.production" ] && scp "$REPO_DIR/.env.production" "${VM_HOST}:${REMOTE_DIR}/.env"

# Step 4: Check for pending migrations
echo "[4/5] Checking for pending migrations..."
PENDING_MIGRATIONS=$(ls -1 "$MIGRATIONS_DIR/"*.sql 2>/dev/null | wc -l)
if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
    echo "Found $PENDING_MIGRATIONS pending migration(s):"
    ls -1 "$MIGRATIONS_DIR/"*.sql 2>/dev/null | xargs -n1 basename
    ssh "$VM_HOST" "mkdir -p $REMOTE_DIR/migrations"
    scp "$MIGRATIONS_DIR/"*.sql "${VM_HOST}:${REMOTE_DIR}/migrations/"
else
    echo "No pending migrations."
fi

# Step 5: Restart containers and run migrations
echo "[5/5] Starting containers..."
ssh "$VM_HOST" << REMOTE_SCRIPT
set -e
cd $REMOTE_DIR

# Stop and remove old containers
docker compose down 2>/dev/null || true

# Start fresh
docker compose up -d

echo ""
echo "Waiting for database..."
sleep 10

# Run pending migrations
if [ -d "migrations" ] && [ "\$(ls -A migrations/*.sql 2>/dev/null)" ]; then
    echo ""
    echo "Running migrations..."

    for migration in migrations/*.sql; do
        if [ -f "\$migration" ]; then
            filename=\$(basename "\$migration")
            echo "  → Running \$filename..."
            if docker exec -i $DB_CONTAINER psql -U $DB_USER -d $DB_NAME < "\$migration" 2>&1; then
                echo "    ✓ \$filename applied"
            else
                echo "    ✗ Migration failed: \$filename (may already be applied)"
            fi
        fi
    done

    # Clean up remote migrations folder after running
    rm -rf migrations/*.sql
    echo "Migrations complete."
else
    echo "No migrations to run."
fi

echo ""
echo "Waiting for services..."
sleep 5
docker compose ps

# Health check
echo ""
curl -s http://localhost:$VM_PORT/health && echo " - App OK" || echo " - App starting..."

# Cleanup old images
docker image prune -f
REMOTE_SCRIPT

# Step 6: Archive applied migrations locally (if any were run)
if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
    echo ""
    echo "[6/6] Archiving applied migrations..."
    mkdir -p "$MIGRATIONS_DIR/applied"
    mv "$MIGRATIONS_DIR/"*.sql "$MIGRATIONS_DIR/applied/" 2>/dev/null || true

    # Commit the archived migrations
    cd "$REPO_DIR"
    if [ -n "$(git status --porcelain "$MIGRATIONS_DIR")" ]; then
        git add "$MIGRATIONS_DIR/"
        git commit -m "chore: archive applied migrations"
        git push
        echo "✓ Migrations archived"
    fi
fi

echo ""
echo "=== Deploy Complete ==="
echo "App: http://${VM_HOST}:${VM_PORT}"
