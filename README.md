# infra — Configuración del VPS Hetzner (91.99.157.147)

Infraestructura como código para el VPS `quotedme-app` en Hetzner CPX32 (4 vCPU, 8 GB RAM, 160 GB NVMe, Ubuntu 24.04).

---

## ⚡ Guía rápida — lo que necesito recordar

```bash
# Conectarme al VPS
ssh root@91.99.157.147

# Ver estado de todo
docker ps --format "table {{.Names}}\t{{.Status}}"
systemctl is-active caddy jobs-dashboard patdilet-web

# Actualizar Hermes (git pull + rebuild)
cd /opt/hermes && git pull && HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build

# Backup de datos (desde mi Mac)
cd '/Volumes/M2 SSD/Repos/PDL/infra' && bash backup.sh

# Migrar a server nuevo
# 1. git clone https://github.com/patdiletx1/infra.git /opt/infra
# 2. bash setup.sh                                  ← configura todo desde cero
# 3. scp backups/<fecha>/* root@nuevo-ip:...         ← restaurar datos
# 4. Reiniciar servicios
```

| Script | Desde | Qué hace |
|--------|-------|----------|
| `setup.sh` | Server nuevo | Instala Docker, Caddy, clona repos, copia configs, inicia todo |
| `backup.sh` | Mi Mac | Descarga state.db, Postgres, WhatsApp sessions, .env — **todo lo necesario para migrar** |

---

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

## Operaciones diarias

### Conectarme al VPS

```bash
ssh root@91.99.157.147
```

### Ver estado de todo

```bash
# Contenedores Docker
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Servicios systemd
systemctl is-active caddy jobs-dashboard patdilet-web

# Logs de Hermes
docker logs hermes --tail 50

# Logs del dashboard
journalctl -u jobs-dashboard --no-pager -n 20

# Memoria
free -h && docker stats hermes --no-stream
```

### Actualizar Hermes Agent

```bash
ssh root@91.99.157.147
cd /opt/hermes

# Ver si hay updates
git fetch origin && git rev-list --count HEAD..origin/main

# Actualizar
git pull origin main
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build

# Post-update: reinstalar Flask (el venv se recrea)
docker exec hermes /usr/local/bin/uv pip install flask
systemctl restart jobs-dashboard
```

### Agregar o modificar un servicio

1. Editar el archivo en este repo (`caddy/Caddyfile`, `systemd/foo.service`, etc.)
2. `git commit && git push`
3. En el VPS: `cd /opt/infra && git pull`
4. Copiar configs a destino y recargar:
   ```bash
   cp caddy/Caddyfile /etc/caddy/ && systemctl reload caddy      # si cambió Caddy
   cp systemd/foo.service /etc/systemd/system/ && systemctl daemon-reload && systemctl restart foo  # si cambió systemd
   cd /opt/hermes && docker compose up -d --build                 # si cambió docker-compose
   ```

### Hacer backup de datos

```bash
# Desde mi Mac
cd '/Volumes/M2 SSD/Repos/PDL/infra'
bash backup.sh
# Los datos quedan en ./backups/<fecha>/
```

---

## Migrar a otro server (guía completa)

### Paso 1: Conseguir un VPS nuevo

- Hetzner CPX32 o similar (4 vCPU, 8 GB RAM)
- Ubuntu 24.04
- Apuntar DNS al nuevo IP (todos los dominios)

### Paso 2: Setup inicial

```bash
# En el server nuevo, como root:
git clone https://github.com/patdiletx1/infra.git /opt/infra

# Copiar los .env con secretos reales desde backup local
# (usando scp desde mi Mac)
scp backups/<fecha>/hermes.env root@<nuevo-ip>:~/.hermes/.env
scp backups/<fecha>/ctrlz.tar.gz root@<nuevo-ip>:/opt/
# ... etc.

# Ejecutar setup
cd /opt/infra && bash setup.sh
```

### Paso 3: Restaurar datos

```bash
# state.db — crítico: historial de conversaciones, memoria, skills
scp backups/<fecha>/hermes-state.db root@<nuevo-ip>:~/.hermes/state.db

# quotedme_scraper — jobs.db del dashboard
scp backups/<fecha>/quotedme_scraper.tar.gz root@<nuevo-ip>:/tmp/
ssh root@<nuevo-ip> "tar xzf /tmp/quotedme_scraper.tar.gz -C ~/.hermes/home/"

# WhatsApp sessions
scp backups/<fecha>/openwa-sessions.tar.gz root@<nuevo-ip>:/tmp/
ssh root@<nuevo-ip> "tar xzf /tmp/openwa-sessions.tar.gz -C ~/.hermes/OpenWA/data/sessions/"

# Postgres (OmniReport)
scp backups/<fecha>/omnireport-pg-dump.sql root@<nuevo-ip>:/tmp/
ssh root@<nuevo-ip> "docker exec -i omnireport-postgres-1 psql -U quotedme < /tmp/omnireport-pg-dump.sql"
```

### Paso 4: Verificar

```bash
# En el nuevo server:
docker ps --format "table {{.Names}}\t{{.Status}}"
curl -sI https://patdilet.dev/ | head -3
curl -sI https://jobs.patdilet.dev/ | head -3
curl -sI https://quotedme.app/health
curl -sI https://ctrlz.app/health
```

---

## Disaster Recovery

Si el VPS muere y necesito recuperar desde cero:

1. **Crear VPS nuevo** en Hetzner (CPX32, Ubuntu 24.04)
2. **Apuntar DNS** al nuevo IP
3. **Clonar este repo**: `git clone https://github.com/patdiletx1/infra.git /opt/infra`
4. **Restaurar secrets**: copiar `.env` desde el último backup (`backups/<fecha>/`)
5. **Ejecutar setup**: `bash /opt/infra/setup.sh`
6. **Restaurar datos**: `state.db`, Postgres dump, WhatsApp sessions
7. **Verificar**: `curl -sI https://patdilet.dev/` → 200

Tiempo estimado: **30-45 minutos** (asumiendo backups recientes).

---

## Actualizar configs desde el server actual

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

Esto descarga todo a `./backups/<fecha>/`. Los `.env` con secretos reales se incluyen en el backup — **NUNCA los commits.**

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
