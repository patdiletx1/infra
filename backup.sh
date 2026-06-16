#!/bin/bash
# backup.sh — Backup de datos del VPS Hetzner
#
# Uso desde tu Mac:
#   bash backup.sh
#
# Hace backup de todo lo necesario para migrar a otro server
# o recuperar ante desastres. Los datos quedan en ./backups/

set -euo pipefail

SERVER="root@91.99.157.147"
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M)"
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[BACKUP]${NC} $1"; }

mkdir -p "$BACKUP_DIR"

# ── 1. Hermes — datos críticos ─────────────────────────────
log "1/6 Respaldando Hermes Agent..."

# state.db — historial de conversaciones, memoria, sesiones
ssh "$SERVER" "ls -lh ~/.hermes/state.db 2>/dev/null" && \
    scp "$SERVER:~/.hermes/state.db" "$BACKUP_DIR/hermes-state.db" || \
    log "   state.db no encontrado"

# config.yaml (para referencia, aunque está en git)
scp "$SERVER:~/.hermes/config.yaml" "$BACKUP_DIR/hermes-config.yaml" 2>/dev/null || true

# auth.json (OAuth tokens)
scp "$SERVER:~/.hermes/auth.json" "$BACKUP_DIR/hermes-auth.json" 2>/dev/null || true

# .env (secrets — SOLO para backup, NUNCA commitear)
scp "$SERVER:~/.hermes/.env" "$BACKUP_DIR/hermes.env" 2>/dev/null || true

# skills creados por el agente
ssh "$SERVER" "tar czf - -C ~/.hermes skills 2>/dev/null" > "$BACKUP_DIR/hermes-skills.tar.gz" 2>/dev/null || true

# ── 2. Hermes — datos de apps internas ─────────────────────
log "2/6 Respaldando apps dentro de Hermes..."

# quotedme_scraper (dashboard + jobs.db + scrapers)
ssh "$SERVER" "tar czf - -C ~/.hermes/home quotedme_scraper 2>/dev/null" > "$BACKUP_DIR/quotedme_scraper.tar.gz" 2>/dev/null || true

# wa-bot (twin.db, configs, sesiones si no son muy grandes)
ssh "$SERVER" "tar czf - -C ~/.hermes wa-bot/data wa-bot/config.yaml wa-bot/.env wa-bot/personalities 2>/dev/null" > "$BACKUP_DIR/wa-bot.tar.gz" 2>/dev/null || true

# patdilet (proyecto Next.js)
ssh "$SERVER" "tar czf - -C ~/.hermes patdilet --exclude='node_modules' --exclude='.next' --exclude='.cache' 2>/dev/null" > "$BACKUP_DIR/patdilet.tar.gz" 2>/dev/null || true

# jarvis
ssh "$SERVER" "tar czf - -C ~/.hermes jarvis 2>/dev/null" > "$BACKUP_DIR/jarvis.tar.gz" 2>/dev/null || true

# ── 3. WhatsApp sessions (OpenWA) ──────────────────────────
log "3/6 Respaldando sesiones WhatsApp..."
ssh "$SERVER" "tar czf - -C ~/.hermes OpenWA/data/sessions --exclude='*.log' --exclude='node_modules' 2>/dev/null" > "$BACKUP_DIR/openwa-sessions.tar.gz" 2>/dev/null || true

# ── 4. Postgres (OmniReport) ───────────────────────────────
log "4/6 Respaldando PostgreSQL..."
ssh "$SERVER" "docker exec omnireport-postgres-1 pg_dumpall -U quotedme 2>/dev/null" > "$BACKUP_DIR/omnireport-pg-dump.sql" 2>/dev/null || log "   No se pudo hacer pg_dump (contenedor corriendo?)"

# ── 5. Ctrlz ───────────────────────────────────────────────
log "5/6 Respaldando Ctrlz..."
ssh "$SERVER" "tar czf - -C /opt/ctrlz .env config.json data 2>/dev/null" > "$BACKUP_DIR/ctrlz.tar.gz" 2>/dev/null || true

# ── 6. Caddy ───────────────────────────────────────────────
log "6/6 Respaldando Caddy..."
scp "$SERVER:/etc/caddy/Caddyfile" "$BACKUP_DIR/Caddyfile" 2>/dev/null || true
ssh "$SERVER" "tar czf - -C /var/lib/caddy .local 2>/dev/null" > "$BACKUP_DIR/caddy-data.tar.gz" 2>/dev/null || true

# ── Resumen ─────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Backup completado: $BACKUP_DIR"
echo "=============================================="
echo ""
ls -lh "$BACKUP_DIR"
echo ""
echo "⚠️  Los archivos .env contienen secretos reales."
echo "    NO los commitees a git."
echo ""
echo "Para migrar a otro server:"
echo "  1. Ejecutar setup.sh en el nuevo server"
echo "  2. Copiar los backups a ~/.hermes/ en el nuevo server"
echo "  3. Restaurar Postgres: docker exec -i omnireport-postgres-1 psql -U quotedme < omnireport-pg-dump.sql"
echo "  4. Reiniciar servicios: docker compose restart"
