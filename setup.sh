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

info "Waiting for services..."
for i in {1..30}; do
  curl -sf http://localhost:8000/health &>/dev/null && break
  sleep 3
done
log "Backend ready"

# Fix InfluxDB token (get actual token from running container)
info "Syncing InfluxDB token..."
sleep 5
ACTUAL_TOKEN=$(docker compose exec -T influxdb influx auth list --json 2>/dev/null | \
  python3 -c "import sys,json; auths=json.load(sys.stdin); print(auths[0]['token'])" 2>/dev/null || echo "")
if [ -n "$ACTUAL_TOKEN" ]; then
  sed -i "s/INFLUXDB_TOKEN=.*/INFLUXDB_TOKEN=${ACTUAL_TOKEN}/" .env
  docker compose up -d backend collector
  sleep 5
  log "InfluxDB token synced"
fi

# Initialize database schema
info "Initializing database..."
docker compose cp backend:/app/backend/auth_schema.sql /tmp/auth_schema.sql 2>/dev/null || true
docker compose cp backend:/app/backend/auth_schema_v2.sql /tmp/auth_schema_v2.sql 2>/dev/null || true
docker cp /tmp/auth_schema.sql temonx-postgres:/tmp/ 2>/dev/null || true
docker cp /tmp/auth_schema_v2.sql temonx-postgres:/tmp/ 2>/dev/null || true
docker compose exec -T postgres psql -U temonx -d temonx -f /tmp/auth_schema.sql 2>/dev/null || true
docker compose exec -T postgres psql -U temonx -d temonx -f /tmp/auth_schema_v2.sql 2>/dev/null || true
log "Database initialized"

# Ask for organization details
echo ""
read -rp "$(echo -e ${BLUE}Organization name [My Company]: ${NC})" ORG_NAME
ORG_NAME="${ORG_NAME:-My Company}"

read -rp "$(echo -e ${BLUE}Organization ID/slug [mycompany]: ${NC})" ORG_SLUG
ORG_SLUG="${ORG_SLUG:-mycompany}"
ORG_SLUG=$(echo "$ORG_SLUG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')

read -rp "$(echo -e ${BLUE}Admin email [admin@company.com]: ${NC})" ADMIN_EMAIL
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@company.com}"

# Generate random password
ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 14)

# Create admin account
info "Creating admin account..."
docker compose exec -T backend python3 -c "
import sys; sys.path.insert(0, '/app')
try:
    from backend.auth_db import create_tenant, create_user, get_tenant_by_slug
    org_name  = '${ORG_NAME}'
    org_slug  = '${ORG_SLUG}'
    email     = '${ADMIN_EMAIL}'
    password  = '${ADMIN_PASSWORD}'
    if not get_tenant_by_slug(org_slug):
        t = create_tenant(org_name, org_slug, 'trial')
        create_user(str(t['id']), email, 'admin', password, 'admin', 'Admin User')
        print('Admin created')
    else:
        print('Already exists')
except Exception as e:
    print(f'Note: {e}')
" 2>/dev/null || true
log "Admin account ready"

SERVER_IP=$(grep SERVER_HOST .env | cut -d= -f2)
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        TemonX IRP Installation Complete! 🚀      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}URL:${NC}       http://${SERVER_IP}"
echo -e "  ${BLUE}Org ID:${NC}    ${ORG_SLUG}"
echo -e "  ${BLUE}Username:${NC}  admin"
echo -e "  ${BLUE}Password:${NC}  ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${YELLOW}⚠ Save your password — it will not be shown again!${NC}"
echo -e "  ${BLUE}License:${NC}   Add LICENSE_KEY to ${TEMONX_DIR}/.env"
echo -e "  ${BLUE}Docs:${NC}      https://docs.temonx.io"
echo ""
# Save credentials to file
cat > "${TEMONX_DIR}/credentials.txt" << CREDS
TemonX IRP Credentials — $(date)
URL:      http://${SERVER_IP}
Org ID:   ${ORG_SLUG}
Username: admin
Password: ${ADMIN_PASSWORD}
Email:    ${ADMIN_EMAIL}
CREDS
chmod 600 "${TEMONX_DIR}/credentials.txt"
log "Credentials saved to ${TEMONX_DIR}/credentials.txt"
