# SIPV Superscript

Script Bash para instalar y levantar **SIPV** automáticamente en una máquina **Ubuntu/Debian** limpia usando **Docker + Docker Compose**.

---

## Qué hace

- Clona el repositorio de SIPV (`AllanHTML5/SIPV`).
- Genera un archivo `.env` con credenciales seguras.
- Levanta MySQL Primary y MySQL Replica.
- Crea la base de datos y el usuario de Django en MySQL.
- Aplica migraciones.
- Crea/asegura el superuser de Django.
- Levanta **Adminer** con acceso externo por defecto.
- Configura **UFW** (firewall).
- Genera `install-summary.txt` con URLs y credenciales.
- Incluye auto-fix para el error intermitente de MySQL root `ERROR 1045` (reinicializa volúmenes si detecta mismatch).

---

## Requisitos

- Ubuntu/Debian (recomendado: Ubuntu 20.04+ / 22.04+).
- Acceso a internet (instalación de paquetes y pull de imágenes).
- Usuario con `sudo` (o ejecutar como `root`).

> El script instala Docker si no existe.

---

## Quick Start

```bash
git clone https://github.com/AllanHTML5/SIPV-Superscript
cd SIPV-Superscript
chmod +x setup.sh
sudo ./setup.sh
```

Al finalizar, se mostrará un resumen en pantalla y también se guardará en:

- `install-summary.txt`

---

## Servicios que levanta

El script levanta estos contenedores:

- `mysql_primary`
- `mysql_replica`
- `sipv_web`
- `adminer`

---

## Accesos

Por defecto:

- App: `http://<TU_IP_PUBLICA>:80`
- Adminer: `http://<TU_IP_PUBLICA>:8080`

Adminer queda expuesto externamente porque en `.env.example` se configura:

```env
ADMINER_BIND_IP=0.0.0.0
ADMINER_PORT=8080
```

---

## Variables de entorno (.env)

Si no existe `.env`, el script lo crea a partir de `.env.example` y genera automáticamente:

- `SECRET_KEY`
- `MYSQL_ROOT_PASSWORD`
- `DB_PASSWORD`
- Credenciales del superuser:
  - `DJANGO_SUPERUSER_USERNAME`
  - `DJANGO_SUPERUSER_EMAIL`
  - `DJANGO_SUPERUSER_PASSWORD`

> Importante: `.env` y `install-summary.txt` contienen credenciales. Protégelos.

---

## Re-ejecutar el script

Si vuelves a ejecutar `setup.sh` en la misma máquina:

- No sobrescribe tu `.env` si ya existe (solo rellena faltantes).
- Vuelve a levantar el stack y re-asegura DB/migraciones/superuser.

---

## MySQL `ERROR 1045` (intermitente)

A veces MySQL puede arrancar con un volumen previo cuyo `root password` no coincide con el `.env` actual.

El script incluye auto-fix:

1. Detecta `ERROR 1045`.
2. Ejecuta `docker compose down -v`.
3. Recrea contenedores y volúmenes.
4. Reintenta el setup.

---

## Comandos útiles

Estos comandos se ejecutan desde el directorio del repo **SIPV** (clonado por el script como `./SIPV`).

### Ver logs del web (DEV)

```bash
docker compose --env-file .env -f docker-compose.dev.yml logs -f web
```

### Detener stack (DEV)

```bash
docker compose --env-file .env -f docker-compose.dev.yml down
```

### Reset total (borra data MySQL)

```bash
docker compose --env-file .env -f docker-compose.dev.yml down -v
```

### Rebuild completo (DEV)

```bash
docker compose --env-file .env -f docker-compose.dev.yml build --no-cache
docker compose --env-file .env -f docker-compose.dev.yml up -d --force-recreate
```

> En PROD, reemplaza `docker-compose.dev.yml` por `docker-compose.prod.yml`.

---

## Seguridad

Adminer expuesto públicamente puede ser útil en cloud, pero no es la opción más segura.

Recomendaciones:

- Cambiar `ADMINER_BIND_IP` a `127.0.0.1` si no necesitas acceso público.
- Restringir el puerto `8080/tcp` en UFW a tu IP (whitelist).
- Usar VPN (Tailscale / ZeroTier).
- Alternativamente, poner Adminer detrás de un reverse proxy con autenticación.

---

## Estructura

- `setup.sh` (script principal)

El script genera dentro del repo SIPV:

- `.env.example` (si no existía)
- `.env` (si no existía)
- `docker-compose.dev.yml`
- `docker-compose.prod.yml`
- `docker/entrypoint.sh` (prod)
- `install-summary.txt`

---

## Troubleshooting

### 1) No abre Adminer desde internet

Verifica:

- `.env`: `ADMINER_BIND_IP=0.0.0.0`
- UFW: debe permitir `8080/tcp` si Adminer está expuesto

```bash
sudo ufw status verbose
```

### 2) App no carga / 400 Bad Request (ALLOWED_HOSTS)

En `dev` el script usa `ALLOWED_HOSTS=*`.

Si estás en `prod`, incluye tu IP o dominio en `ALLOWED_HOSTS`.

