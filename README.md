# infra — Configuración del VPS Hetzner (91.99.157.147)

Infraestructura como código para el VPS `quotedme-app` en Hetzner CPX32 (4 vCPU, 8 GB RAM, 160 GB NVMe, Ubuntu 24.04).

## Servicios

| Servicio | Dominio | Tipo | Puerto |
|----------|---------|------|--------|
| Hermes Agent | Telegram `@patdilethermes_bot` | Docker (host network) | — |
| OmniReport | `quotedme.app` | Docker Compose | 3000, 3001 |
| Ctrlz | `ctrlz.app` | Docker Compose | 5000, 5002 |
| DeliveryCheck | `deliverycheck.ctrlz.app` | Docker Compose | 8000, 3002 |
| patdilet.dev | `patdilet.dev` | systemd (Next.js en Hermes) | 3003 |
| Job Tracker | `jobs.patdilet.dev` | systemd (Flask en Hermes) | 5003 |
| Caddy | reverse proxy + SSL | bare-metal systemd | 80, 443 |

## Estructura

```
infra/
├── README.md
├── setup.sh                     # Script de instalación desde cero
├── hermes/
│   ├── docker-compose.yml       # Gateway + dashboard (profile)
│   ├── config.yaml              # Config sin secretos (api_key usa DEEPSEEK_API_KEY)
│   └── .env.example             # Template de variables de entorno
├── caddy/
│   └── Caddyfile                # Reverse proxy + SSL automático
├── systemd/
│   ├── jobs-dashboard.service   # Flask dashboard en :5003
│   └── patdilet-web.service     # Next.js en :3003
├── ctrlz/
│   ├── docker-compose.yml
│   └── .env.example
├── omnireport/
│   ├── docker-compose.yml
│   └── .env.example
└── deliverycheck/
    ├── docker-compose.yml
    └── .env.example
```

## Cómo usar

### Setup inicial en un server nuevo

```bash
# 1. Clonar este repo
git clone git@github.com:patdiletx1/infra.git /opt/infra

# 2. Copiar los .env con secretos reales (NUNCA en git)
#    desde tu backup local al server

# 3. Ejecutar setup
cd /opt/infra && bash setup.sh
```

### Actualizar configs desde el server actual

```bash
ssh root@91.99.157.147
cd /opt/infra
git pull
# Aplicar cambios (copiar configs, recargar systemd, etc.)
```

### Agregar un servicio nuevo

1. Crear carpeta `nuevo-servicio/` con su config
2. Agregar entrada en Caddyfile
3. Agregar pasos en `setup.sh`
4. `git commit && git push`

## Datos y Backup

El repo versiona **configuración**, no **datos**. Para migrar a otro server necesitás ambos.

### Qué está versionado (config)
- Docker Compose files, Caddyfile, systemd units, Hermes config

### Qué NO está versionado (datos — requiere backup)

| Dato | Ubicación | Importancia |
|------|-----------|-------------|
| `state.db` | `~/.hermes/state.db` | 🔴 Crítico — historial de conversaciones, memoria, skills |
| `auth.json` | `~/.hermes/auth.json` | 🟡 OAuth tokens de proveedores |
| `quotedme_scraper/` | `~/.hermes/home/quotedme_scraper/` | 🟡 Dashboard Flask, jobs.db |
| `wa-bot/` | `~/.hermes/wa-bot/` | 🟡 twin.db, configs WhatsApp |
| `jarvis/` | `~/.hermes/jarvis/` | 🟢 Asistente de voz |
| OpenWA sessions | `~/.hermes/OpenWA/data/sessions/` | 🟡 Sesiones WhatsApp (~600 MB) |
| Postgres | Docker volume `pgdata` | 🔴 OmniReport DB |
| Redis | Docker volume `redisdata` | 🟢 Cache (regenerable) |

### Hacer backup

```bash
# Desde tu Mac
cd /Volumes/M2\ SSD/Repos/PDL/infra
bash backup.sh
```

Esto descarga todo a `./backups/<fecha>/`. Los `.env` con secretos reales se incluyen en el backup — **NUNCA los commitees.**

### Migrar a otro server

```bash
# 1. Configurar desde cero
git clone https://github.com/patdiletx1/infra.git /opt/infra
bash /opt/infra/setup.sh

# 2. Restaurar datos desde backup
scp backups/20260616-*/hermes-state.db root@nuevo-server:~/.hermes/state.db
scp -r backups/20260616-*/quotedme_scraper root@nuevo-server:~/.hermes/home/
# ... etc.

# 3. Restaurar Postgres
scp backups/20260616-*/omnireport-pg-dump.sql root@nuevo-server:/tmp/
ssh root@nuevo-server "docker exec -i omnireport-postgres-1 psql -U quotedme < /tmp/omnireport-pg-dump.sql"

# 4. Reiniciar
ssh root@nuevo-server "cd /opt/hermes && docker compose restart"
```

## Secrets — NUNCA en git

Los `.env` reales contienen API keys, tokens, y contraseñas. Se respaldan aparte:

- **Local**: `~/.hermes/.env`, `/opt/ctrlz/.env`, `/opt/OmniReport/.env`, `/opt/deliverycheck/.env`
- **Backup**: En `~/.hermes.backup.*/` en el VPS, o en `scp` local
- **Template**: `.env.example` en cada carpeta (sin valores reales)

## Costo mensual

| Recurso | Costo aprox |
|---------|------------|
| CPX32 VPS | ~€10-12/mo |
| Object Storage (1 TB) | ~€5/mo |
| **Total** | **~€15-17/mo** |
