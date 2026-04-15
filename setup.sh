#!/bin/bash
# TemonX IRP — One-Command Installer
set -e

TEMONX_DIR="${TEMONX_DIR:-/opt/temonx}"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo -e "${BLUE}TemonX IRP — Intelligent Routing Platform${NC}"
echo ""

[[ $EUID -ne 0 ]] && err "Run as root: sudo bash setup.sh"
command -v docker &>/dev/null || err "Docker required. Install: https://docs.docker.com/engine/install/"

mkdir -p "${TEMONX_DIR}/data"
cd "${TEMONX_DIR}"

if [ ! -f docker-compose.yml ]; then
  info "Downloading TemonX IRP..."
  BASE="https://raw.githubusercontent.com/Lookin-Link/temonx-irp-deploy/main"
  curl -sSL "${BASE}/docker-compose.yml" -o docker-compose.yml
  curl -sSL "${BASE}/.env.example" -o .env.example
  log "Downloaded"
fi

if [ ! -f .env ]; then
  SERVER_IP=$(hostname -I | awk '{print $1}')
  SECRET_KEY=$(openssl rand -hex 32)
  POSTGRES_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 18)
  INFLUXDB_TOKEN=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
  INFLUXDB_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)

  sed -e "s|your-server-ip|${SERVER_IP}|g" \
      -e "s|change-this-to-random-64-chars|${SECRET_KEY}|g" \
      -e "s|POSTGRES_PASSWORD=change-this-password|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|g" \
      -e "s|INFLUXDB_TOKEN=change-this-token|INFLUXDB_TOKEN=${INFLUXDB_TOKEN}|g" \
      -e "s|INFLUXDB_PASSWORD=change-this-password|INFLUXDB_PASSWORD=${INFLUXDB_PASSWORD}|g" \
      .env.example > .env
  log "Created .env"
fi

if [ -t 0 ]; then
  echo ""
  read -rp "$(echo -e ${BLUE}Enter your TemonX license key [Enter for trial]: ${NC})" LICENSE_KEY
  if [ -n "$LICENSE_KEY" ]; then
    sed -i "s/LICENSE_KEY=.*/LICENSE_KEY=${LICENSE_KEY}/" .env
    log "License key saved"
  else
    warn "Trial mode — 3 links, 1 router"
  fi
fi

info "Pulling images..."
docker compose pull

info "Starting TemonX IRP..."
docker compose up -d

info "Waiting for backend..."
for i in {1..30}; do
  curl -sf http://localhost:8000/health &>/dev/null && log "Backend ready" && break
  sleep 3
done

info "Creating admin account..."
docker compose exec -T backend python3 -c "
import sys; sys.path.insert(0, '/app')
try:
    from backend.auth_db import create_tenant, create_user, get_tenant_by_slug
    if not get_tenant_by_slug('admin'):
        t = create_tenant('Admin', 'admin', 'enterprise')
        create_user(str(t['id']), 'admin@temonx.io', 'admin', 'TemonX-Admin-2026!', 'admin', 'Admin User')
        print('Admin created')
    else:
        print('Already exists')
except Exception as e:
    print(f'Note: {e}')
" 2>/dev/null || true

SERVER_IP=$(grep SERVER_HOST .env | cut -d= -f2)
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     TemonX IRP Installation Complete!    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}URL:${NC}       http://${SERVER_IP}"
echo -e "  ${BLUE}Username:${NC}  admin"
echo -e "  ${BLUE}Password:${NC}  TemonX-Admin-2026!"
echo ""
echo -e "  ${YELLOW}⚠ Change default password immediately!${NC}"
echo -e "  ${BLUE}Docs:${NC}      https://docs.temonx.io"
echo ""
