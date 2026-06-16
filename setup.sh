#!/bin/bash
# setup.sh — Reconstruye el VPS Hetzner completo desde cero
#
# Uso:  bash setup.sh
#
# Requisitos previos:
#   1. Ubuntu 24.04 instalado
#   2. DNS apuntando al server (A records para todos los dominios)
#   3. .env files con secretos reales en /opt/infra/secrets/ (NO en git)
#
# Los .env se copian desde /opt/infra/secrets/ a sus ubicaciones:
#   secrets/hermes.env       → ~/.hermes/.env
#   secrets/ctrlz.env        → /opt/ctrlz/.env
#   secrets/omnireport.env   → /opt/OmniReport/.env
#   secrets/deliverycheck.env → /opt/deliverycheck/.env

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────
log "Verificando sistema..."
[ "$(id -u)" -eq 0 ] || err "Ejecutar como root"
grep -q "Ubuntu" /etc/os-release || warn "Se espera Ubuntu 24.04"

# ── 1. Dependencias del sistema ────────────────────────────
log "1/7 Instalando dependencias..."
apt-get update -qq
apt-get install -y -qq curl wget git ca-certificates gnupg lsb-release

# Docker
if ! command -v docker &>/dev/null; then
    log "   Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
fi

# Caddy
if ! command -v caddy &>/dev/null; then
    log "   Instalando Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy
fi

log "   Docker $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
log "   Caddy $(caddy version | head -1)"

# ── 2. Clonar repos de apps ────────────────────────────────
log "2/7 Clonando repositorios..."

# Hermes Agent
if [ ! -d /opt/hermes ]; then
    git clone https://github.com/NousResearch/hermes-agent.git /opt/hermes
fi

# Ctrlz (asumiendo repo en GitHub — ajustar URL)
# git clone git@github.com:patdiletx1/ctrlz.git /opt/ctrlz

# OmniReport (privado — ajustar URL)
# git clone git@github.com:patdilet-ai/OmniReport.git /opt/OmniReport

# DeliveryCheck
# git clone git@github.com:patdiletx1/deliverycheck.git /opt/deliverycheck

# Si los repos ya existen en /opt/, solo actualizar:
for dir in hermes ctrlz OmniReport deliverycheck; do
    if [ -d "/opt/$dir/.git" ]; then
        log "   Actualizando /opt/$dir..."
        (cd "/opt/$dir" && git pull --ff-only 2>/dev/null) || warn "   No se pudo actualizar /opt/$dir (repo local?)"
    fi
done

# ── 3. Configurar Hermes ───────────────────────────────────
log "3/7 Configurando Hermes Agent..."

mkdir -p ~/.hermes/logs
cp hermes/docker-compose.yml /opt/hermes/docker-compose.yml
cp hermes/config.yaml ~/.hermes/config.yaml

# Secrets
if [ -f secrets/hermes.env ]; then
    cp secrets/hermes.env ~/.hermes/.env
    chmod 600 ~/.hermes/.env
    log "   ~/.hermes/.env instalado"
else
    warn "   secrets/hermes.env no encontrado — copia hermes/.env.example y llénalo"
fi

# Build & start
cd /opt/hermes
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build

# ── 4. Configurar Caddy ────────────────────────────────────
log "4/7 Configurando Caddy..."
cp caddy/Caddyfile /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl enable caddy --now
systemctl reload caddy

# ── 5. Instalar systemd units ──────────────────────────────
log "5/7 Instalando systemd units..."
cp systemd/jobs-dashboard.service /etc/systemd/system/
cp systemd/patdilet-web.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable jobs-dashboard.service patdilet-web.service

# ⚠️ Estos servicios dependen del contenedor hermes.
# Si Hermes no está corriendo todavía (build), systemd los reintentará.
systemctl start jobs-dashboard.service patdilet-web.service 2>/dev/null || warn "   Systemd units se iniciarán cuando Hermes esté listo"

# ── 6. Instalar Flask en venv de Hermes ────────────────────
log "6/7 Instalando Flask en venv de Hermes..."
sleep 10  # Esperar a que el contenedor termine de iniciar
if docker exec hermes /usr/local/bin/uv pip install flask 2>/dev/null; then
    log "   Flask instalado"
else
    warn "   No se pudo instalar Flask — reintentar manualmente"
fi

# ── 7. Otros servicios Docker ──────────────────────────────
log "7/7 Iniciando servicios adicionales..."

# Ctrlz
if [ -f ctrlz/docker-compose.yml ]; then
    cp ctrlz/docker-compose.yml /opt/ctrlz/docker-compose.yml
    if [ -f secrets/ctrlz.env ]; then
        cp secrets/ctrlz.env /opt/ctrlz/.env
        chmod 600 /opt/ctrlz/.env
    fi
    (cd /opt/ctrlz && docker compose up -d --build) || warn "Ctrlz no inició"
fi

# OmniReport
if [ -f omnireport/docker-compose.yml ]; then
    cp omnireport/docker-compose.yml /opt/OmniReport/docker-compose.yml
    if [ -f secrets/omnireport.env ]; then
        cp secrets/omnireport.env /opt/OmniReport/.env
        chmod 600 /opt/OmniReport/.env
    fi
    (cd /opt/OmniReport && docker compose up -d) || warn "OmniReport no inició"
fi

# DeliveryCheck
if [ -f deliverycheck/docker-compose.yml ]; then
    cp deliverycheck/docker-compose.yml /opt/deliverycheck/docker-compose.yml
    if [ -f secrets/deliverycheck.env ]; then
        cp secrets/deliverycheck.env /opt/deliverycheck/.env
        chmod 600 /opt/deliverycheck/.env
    fi
    (cd /opt/deliverycheck && docker compose up -d --build) || warn "DeliveryCheck no inició"
fi

# ── Resumen ─────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Setup completado"
echo "=============================================="
echo ""
echo "Servicios:"
docker ps --format "  {{.Names}} — {{.Status}}"
echo ""
echo "Systemd:"
systemctl is-active caddy jobs-dashboard patdilet-web 2>/dev/null
echo ""
echo "Verificar:"
echo "  curl -sI https://quotedme.app/health"
echo "  curl -sI https://ctrlz.app/health"
echo "  curl -sI https://patdilet.dev/"
echo "  curl -sI https://jobs.patdilet.dev/"
echo "  curl -sI https://deliverycheck.ctrlz.app/"
echo ""
echo "Si algún servicio no arrancó, revisar logs:"
echo "  docker logs hermes --tail 50"
echo "  journalctl -u jobs-dashboard --no-pager -n 20"
