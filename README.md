# Agent-Deploy

Deployment scripts optimized for AI coding assistant workflows.

## The Problem

When working with AI coding assistants (Claude Code, GitHub Copilot, etc.), verbose deployment output consumes context tokens unnecessarily. A typical Docker build can output hundreds of lines that provide no value to the AI assistant.

## The Solution

Two deployment scripts:

### `deploy.sh` - Verbose (Human-Friendly)

Full output for manual debugging and monitoring. Shows every step of:
- Git commit/push
- Docker build progress
- Image transfer
- Migration execution
- Container startup

### `agent-deploy.sh` - Minimal (AI-Friendly)

Outputs only key milestones:
```
Deployment started
Committing to GitHub...
Building image...
Transferring to VM...
Restarting containers...
Deployment complete
Status: OK - http://YOUR_VM_IP:3000
```

Full logs are written to `/tmp/deploy.log` for debugging if needed.

## Usage

```bash
# Full deploy
./agent-deploy.sh        # Minimal output (for AI sessions)
./deploy.sh              # Verbose output (for humans)

# Quick restart (container only)
./agent-deploy.sh quick
./deploy.sh quick
```

## Configuration

Edit the configuration section at the top of each script, or set environment variables:

```bash
export VM_HOST="192.168.1.100"
export VM_PORT="3000"
export REMOTE_DIR="/home/deploy/app"
export IMAGE_NAME="myapp:latest"
export DB_CONTAINER="app-db"
export DB_USER="postgres"
export DB_NAME="appdb"
```

## Features

- **Git integration**: Auto-commits and pushes before deploy
- **Docker build**: Builds image locally with build args (commit hash, build time)
- **Image transfer**: Saves and loads Docker image to remote VM via SSH
- **Config sync**: Transfers docker-compose.yml and .env files
- **Migrations**: Detects, transfers, and runs SQL migrations automatically
- **Migration archival**: Moves applied migrations to `applied/` folder and commits
- **Health check**: Verifies deployment success

## Requirements

- Docker (local machine)
- SSH access to remote VM (key-based auth recommended)
- Docker and docker-compose on remote VM
- Git repository

## Directory Structure

```
your-project/
├── Dockerfile
├── docker-compose.yml
├── .env.production
├── deploy.sh
├── agent-deploy.sh
└── migrations/
    ├── 001_initial.sql
    ├── 002_add_users.sql
    └── applied/           # Auto-created, holds completed migrations
```

## License

MIT
