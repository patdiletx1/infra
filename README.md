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
