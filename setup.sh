#!/usr/bin/env bash
set -euo pipefail

# =========================
# SIPV - Setup Automatizado
# Ubuntu/Debian
# Por Allan Flores
# V1
# =========================

PROJECT_NAME="SIPV"
REPO_URL="https://github.com/AllanHTML5/SIPV"
ENV_FILE=".env"
ENV_EXAMPLE_FILE=".env.example"
COMPOSE_DEV="docker-compose.dev.yml"
COMPOSE_PROD="docker-compose.prod.yml"
ENTRYPOINT_SH="docker/entrypoint.sh"
SUMMARY_FILE="install-summary.txt"

log()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }
die()  { err "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Falta comando: $1"; }

is_root() { [[ "${EUID}" -eq 0 ]]; }
has_sudo() { command -v sudo >/dev/null 2>&1; }

run_as_root() {
  if is_root; then
    bash -lc "$*"
  else
    has_sudo || die "Necesitas sudo (o ejecutar como root)."
    sudo bash -lc "$*"
  fi
}

detect_os() {
  [[ -f /etc/os-release ]] || die "No encuentro /etc/os-release. ¿Esto es Linux?"
  . /etc/os-release
  echo "${ID:-unknown}"
}

ensure_repo_root_or_clone() {
  if [[ -f "Dockerfile" && -d "backend" ]]; then
    log "Repo detectado (Dockerfile + backend/)."
    return 0
  fi

  warn "No veo el repo en el directorio actual."
  need_cmd git
  local target_dir="./SIPV"
  if [[ -d "$target_dir" ]]; then
    warn "Ya existe $target_dir/. Entrando ahí..."
    cd "$target_dir"
    return 0
  fi

  log "Clonando repo: $REPO_URL"
  git clone "$REPO_URL" "$target_dir"
  cd "$target_dir"
}

fix_dockerfile_if_needed() {
  if [[ -f "Dockerfile" ]]; then
    local first
    first="$(head -n 1 Dockerfile || true)"
    if [[ "$first" =~ ^OM[[:space:]]+python: ]]; then
      warn "Dockerfile parece tener 'OM python:...' -> corrigiendo a 'FROM python:...'"
      run_as_root "sed -i '1s/^OM[[:space:]]\\+/FROM /' Dockerfile"
    fi
  fi
}

gen_secret_key() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n' || true
  fi
}

gen_password() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
  else
    head -c 24 /dev/urandom | base64 | tr -d '\n' || true
  fi
}

get_private_ip() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  echo "${ip:-127.0.0.1}"
}

get_public_ip() {
  local ip=""
  ip="$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsSL --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)"
  fi
  echo "$ip"
}

escape_sed_repl() {
  echo "$1" | sed -e 's/[\/&|\\]/\\&/g'
}

set_env_var() {
  local key="$1"
  local val="$2"
  local esc
  esc="$(escape_sed_repl "$val")"

  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*$|${key}=${esc}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

get_env_var() {
  local key="$1"
  if [[ -f "$ENV_FILE" ]]; then
    awk -F= -v k="$key" 'BEGIN{found=0} $1==k{found=1; sub(/^k=/,""); print substr($0, index($0,$2)); exit} END{if(!found) exit 1}' "$ENV_FILE" 2>/dev/null || return 1
  else
    return 1
  fi
}

detect_allowed_hosts_delim() {
  local f=""
  if [[ -f "backend/backend/settings.py" ]]; then f="backend/backend/settings.py"; fi
  if [[ -z "$f" && -f "backend/settings.py" ]]; then f="backend/settings.py"; fi

  if [[ -n "$f" ]]; then
    if grep -Eq "ALLOWED_HOSTS.*split\(\s*['\"][[:space:]]*,[[:space:]]*['\"]\s*\)" "$f"; then
      echo "comma"
      return 0
    fi
    if grep -Eq "ALLOWED_HOSTS.*split\(\s*\)" "$f"; then
      echo "space"
      return 0
    fi
  fi

  echo "comma"
}

write_env_example_if_missing() {
  if [[ -f "$ENV_EXAMPLE_FILE" ]]; then
    log "$ENV_EXAMPLE_FILE ya existe."
    return 0
  fi

  log "Creando $ENV_EXAMPLE_FILE"
  cat > "$ENV_EXAMPLE_FILE" <<'EOF'
# =========================
# SIPV - Variables de entorno
# =========================

# ---- App ----
SECRET_KEY=
DEBUG=True
ALLOWED_HOSTS=
LANGUAGE_CODE=es-hn
TIME_ZONE=America/Tegucigalpa

# ---- DB (Django) ----
DB_NAME=sipv
DB_USER=sipvuser
DB_PASSWORD=
DB_HOST=mysql_primary
DB_PORT=3306

# ---- MySQL root ----
MYSQL_ROOT_PASSWORD=

# ---- Ports (HOST) ----
WEB_BIND_IP=0.0.0.0
WEB_PORT=80

ADMINER_BIND_IP=0.0.0.0
ADMINER_PORT=8080

MYSQL_PRIMARY_BIND_IP=127.0.0.1
MYSQL_PRIMARY_PORT=3307

MYSQL_REPLICA_BIND_IP=127.0.0.1
MYSQL_REPLICA_PORT=3308

# ---- Modo de despliegue ----
SIPV_MODE=dev

# ---- Django superuser (auto) ----
DJANGO_SUPERUSER_USERNAME=
DJANGO_SUPERUSER_EMAIL=
DJANGO_SUPERUSER_PASSWORD= 

# ---- Gunicorn ----
GUNICORN_WORKERS=3
EOF
}

bootstrap_env_if_missing() {
  if [[ -f "$ENV_FILE" ]]; then
    log "$ENV_FILE ya existe."
    return 0
  fi

  log "Creando $ENV_FILE desde $ENV_EXAMPLE_FILE con valores generados"
  cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
  chmod 600 "$ENV_FILE" || true

  local private_ip public_ip
  private_ip="$(get_private_ip)"
  public_ip="$(get_public_ip || true)"

  local secret mysql_root db_pass su_user su_email su_pass mode delim hosts

  secret="$(gen_secret_key)"
  mysql_root="$(gen_password)"
  db_pass="$(gen_password)"
  su_user="admin"
  su_email="admin@local.com"
  su_pass="$(gen_password)"
  mode="$(grep -E '^SIPV_MODE=' "$ENV_FILE" | cut -d= -f2- || true)"
  mode="${mode:-dev}"

  delim="$(detect_allowed_hosts_delim)"

  if [[ "$mode" == "dev" ]]; then
    hosts="*"
  else
    if [[ -n "$public_ip" ]]; then
      if [[ "$delim" == "space" ]]; then
        hosts="localhost 127.0.0.1 ${private_ip} ${public_ip}"
      else
        hosts="localhost,127.0.0.1,${private_ip},${public_ip}"
      fi
    else
      if [[ "$delim" == "space" ]]; then
        hosts="localhost 127.0.0.1 ${private_ip}"
      else
        hosts="localhost,127.0.0.1,${private_ip}"
      fi
    fi
  fi

  set_env_var "SECRET_KEY" "$secret"
  set_env_var "MYSQL_ROOT_PASSWORD" "$mysql_root"
  set_env_var "DB_PASSWORD" "$db_pass"
  set_env_var "ADMINER_BIND_IP" "0.0.0.0"

  if ! grep -qE '^DB_USER=' "$ENV_FILE"; then
    set_env_var "DB_USER" "sipvuser"
  fi

  local dbg
  dbg="$(grep -E '^DEBUG=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$dbg" ]]; then
    set_env_var "DEBUG" "True"
  elif [[ "$dbg" == "1" ]]; then
    set_env_var "DEBUG" "True"
  elif [[ "$dbg" == "0" ]]; then
    set_env_var "DEBUG" "False"
  fi

  if ! grep -qE '^ALLOWED_HOSTS=.+$' "$ENV_FILE"; then
    set_env_var "ALLOWED_HOSTS" "$hosts"
  else
    local cur=""
    cur="$(grep -E '^ALLOWED_HOSTS=' "$ENV_FILE" | cut -d= -f2- || true)"
    if [[ -z "$cur" ]]; then
      set_env_var "ALLOWED_HOSTS" "$hosts"
    fi
  fi

  set_env_var "DJANGO_SUPERUSER_USERNAME" "$su_user"
  set_env_var "DJANGO_SUPERUSER_EMAIL" "$su_email"
  set_env_var "DJANGO_SUPERUSER_PASSWORD" "$su_pass"

  log "$ENV_FILE creado. Puedes editarlo si deseas (no es obligatorio)."
}

ensure_env_has_generated_values() {
  local private_ip public_ip
  private_ip="$(get_private_ip)"
  public_ip="$(get_public_ip || true)"

  local cur=""
  cur="$(grep -E '^SECRET_KEY=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "SECRET_KEY" "$(gen_secret_key)"
  fi

  cur="$(grep -E '^DEBUG=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "DEBUG" "True"
  elif [[ "$cur" == "1" ]]; then
    set_env_var "DEBUG" "True"
  elif [[ "$cur" == "0" ]]; then
    set_env_var "DEBUG" "False"
  fi

  cur="$(grep -E '^MYSQL_ROOT_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "MYSQL_ROOT_PASSWORD" "$(gen_password)"
  fi

  cur="$(grep -E '^DB_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "DB_PASSWORD" "$(gen_password)"
  fi

  cur="$(grep -E '^DJANGO_SUPERUSER_USERNAME=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "DJANGO_SUPERUSER_USERNAME" "admin"
  fi
  cur="$(grep -E '^DJANGO_SUPERUSER_EMAIL=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "DJANGO_SUPERUSER_EMAIL" "admin@local.com"
  fi
  cur="$(grep -E '^DJANGO_SUPERUSER_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "DJANGO_SUPERUSER_PASSWORD" "$(gen_password)"
  fi

  cur="$(grep -E '^ADMINER_BIND_IP=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    set_env_var "ADMINER_BIND_IP" "0.0.0.0"
  fi

  local mode delim hosts
  mode="$(grep -E '^SIPV_MODE=' "$ENV_FILE" | cut -d= -f2- || true)"
  mode="${mode:-dev}"
  delim="$(detect_allowed_hosts_delim)"

  cur="$(grep -E '^ALLOWED_HOSTS=' "$ENV_FILE" | cut -d= -f2- || true)"
  if [[ -z "$cur" ]]; then
    if [[ "$mode" == "dev" ]]; then
      hosts="*"
    else
      if [[ -n "$public_ip" ]]; then
        if [[ "$delim" == "space" ]]; then
          hosts="localhost 127.0.0.1 ${private_ip} ${public_ip}"
        else
          hosts="localhost,127.0.0.1,${private_ip},${public_ip}"
        fi
      else
        if [[ "$delim" == "space" ]]; then
          hosts="localhost 127.0.0.1 ${private_ip}"
        else
          hosts="localhost,127.0.0.1,${private_ip}"
        fi
      fi
    fi
    set_env_var "ALLOWED_HOSTS" "$hosts"
  fi
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "No existe $ENV_FILE"
  set -a
  . "./$ENV_FILE"
  set +a
}

install_base_packages() {
  log "Instalando paquetes base (git, curl, ufw, etc.)"
  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get update -y"
  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get install -y --no-install-recommends \
    git curl ca-certificates gnupg lsb-release \
    ufw iptables jq \
    netcat-openbsd \
    default-libmysqlclient-dev gcc pkg-config \
    libcairo2 pango1.0-tools libpango-1.0-0 \
    libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 \
    libffi-dev libssl-dev fonts-dejavu"
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker ya está instalado."
    return 0
  fi

  log "Instalando Docker Engine (repo oficial)"
  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get update -y"
  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true"
  run_as_root "install -m 0755 -d /etc/apt/keyrings"
  run_as_root "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || true"
  run_as_root "chmod a+r /etc/apt/keyrings/docker.asc"

  local codename=""
  if command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs)"
  else
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
  fi
  [[ -n "$codename" ]] || die "No pude detectar VERSION_CODENAME para Docker repo."

  run_as_root "echo \
    \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    ${codename} stable\" > /etc/apt/sources.list.d/docker.list"

  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get update -y"
  run_as_root "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  run_as_root "systemctl enable --now docker"
  log "Docker instalado y servicio iniciado."
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "docker compose OK."
  else
    die "No encuentro 'docker compose'. Asegúrate de tener docker-compose-plugin instalado."
  fi
}

add_user_to_docker_group() {
  local user="${SUDO_USER:-$USER}"
  if id -nG "$user" | grep -qw docker; then
    log "Usuario '$user' ya está en el grupo docker."
    return 0
  fi

  warn "Agregando '$user' al grupo docker (para no usar sudo)."
  run_as_root "usermod -aG docker '$user'"

  warn "IMPORTANTE: cierra sesión y vuelve a entrar para aplicar el grupo docker."
  warn "Mientras tanto, el script seguirá usando sudo donde haga falta."
}

setup_ufw() {
  log "Configurando UFW (firewall)"
  run_as_root "ufw --force reset"
  run_as_root "ufw default deny incoming"
  run_as_root "ufw default allow outgoing"
  run_as_root "ufw allow OpenSSH"

  if [[ "${WEB_BIND_IP:-0.0.0.0}" == "0.0.0.0" ]]; then
    run_as_root "ufw allow ${WEB_PORT:-80}/tcp"
  else
    log "WEB_BIND_IP != 0.0.0.0 -> no abro WEB_PORT en UFW (solo local)."
  fi

  if [[ "${ADMINER_BIND_IP:-127.0.0.1}" == "0.0.0.0" ]]; then
    warn "ADMINER está expuesto públicamente. Abriendo puerto ${ADMINER_PORT:-8080}/tcp."
    run_as_root "ufw allow ${ADMINER_PORT:-8080}/tcp"
  else
    log "Adminer solo local."
  fi

  run_as_root "ufw --force enable"
  run_as_root "ufw status verbose | sed -n '1,200p'"
  log "UFW listo."
}

write_entrypoint_prod() {
  mkdir -p docker
  if [[ -f "$ENTRYPOINT_SH" ]]; then
    log "$ENTRYPOINT_SH ya existe."
    return 0
  fi

  log "Creando entrypoint de producción: $ENTRYPOINT_SH"
  cat > "$ENTRYPOINT_SH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "[entrypoint] waiting for DB ${DB_HOST}:${DB_PORT}..."
for i in {1..60}; do
  nc -z "${DB_HOST}" "${DB_PORT}" && break
  sleep 1
done

echo "[entrypoint] migrate..."
python manage.py migrate --noinput

echo "[entrypoint] collectstatic..."
python manage.py collectstatic --noinput || true

echo "[entrypoint] starting: $*"
exec "$@"
EOF
  chmod +x "$ENTRYPOINT_SH"
}

write_compose_files() {
  log "Generando $COMPOSE_DEV y $COMPOSE_PROD basados en .env"

  cat > "$COMPOSE_DEV" <<'EOF'
services:
  mysql_primary:
    image: mysql:8.0
    container_name: mysql_primary
    restart: unless-stopped
    command: ["--default-authentication-plugin=mysql_native_password"]
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "${MYSQL_PRIMARY_BIND_IP}:${MYSQL_PRIMARY_PORT}:3306"
    volumes:
      - primary_data:/var/lib/mysql
      - ./docker/mysql/global/my.cnf:/etc/mysql/my.cnf:ro
      - ./docker/mysql/primary/my.cnf:/etc/mysql/conf.d/my.cnf:ro
      - ./docker/mysql/primary/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: [sipv_net]

  mysql_replica:
    image: mysql:8.0
    container_name: mysql_replica
    restart: unless-stopped
    command: ["--default-authentication-plugin=mysql_native_password"]
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "${MYSQL_REPLICA_BIND_IP}:${MYSQL_REPLICA_PORT}:3306"
    volumes:
      - replica_data:/var/lib/mysql
      - ./docker/mysql/replica/my.cnf:/etc/mysql/conf.d/my.cnf:ro
    depends_on:
      mysql_primary:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: [sipv_net]

  web:
    build: .
    container_name: sipv_web
    restart: unless-stopped
    env_file: .env
    environment:
      DB_HOST: ${DB_HOST}
      DB_PORT: "${DB_PORT}"
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DEBUG: "${DEBUG}"
      ALLOWED_HOSTS: "${ALLOWED_HOSTS}"
      SECRET_KEY: "${SECRET_KEY}"
      LANGUAGE_CODE: "${LANGUAGE_CODE}"
      TIME_ZONE: "${TIME_ZONE}"
      DJANGO_SUPERUSER_USERNAME: "${DJANGO_SUPERUSER_USERNAME}"
      DJANGO_SUPERUSER_EMAIL: "${DJANGO_SUPERUSER_EMAIL}"
      DJANGO_SUPERUSER_PASSWORD: "${DJANGO_SUPERUSER_PASSWORD}"
    volumes:
      - ./backend:/app
      - ./staticfiles:/app/staticfiles
    depends_on:
      mysql_primary:
        condition: service_healthy
    ports:
      - "${WEB_BIND_IP}:${WEB_PORT}:8000"
    command: bash -lc "python manage.py migrate && python manage.py runserver 0.0.0.0:8000"
    networks: [sipv_net]

  adminer:
    image: adminer:latest
    container_name: adminer
    restart: unless-stopped
    depends_on:
      mysql_primary:
        condition: service_healthy
    ports:
      - "${ADMINER_BIND_IP}:${ADMINER_PORT}:8080"
    networks: [sipv_net]

volumes:
  primary_data:
  replica_data:

networks:
  sipv_net:
    driver: bridge
EOF

  cat > "$COMPOSE_PROD" <<'EOF'
services:
  mysql_primary:
    image: mysql:8.0
    container_name: mysql_primary
    restart: unless-stopped
    command: ["--default-authentication-plugin=mysql_native_password"]
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "${MYSQL_PRIMARY_BIND_IP}:${MYSQL_PRIMARY_PORT}:3306"
    volumes:
      - primary_data:/var/lib/mysql
      - ./docker/mysql/global/my.cnf:/etc/mysql/my.cnf:ro
      - ./docker/mysql/primary/my.cnf:/etc/mysql/conf.d/my.cnf:ro
      - ./docker/mysql/primary/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: [sipv_net]

  mysql_replica:
    image: mysql:8.0
    container_name: mysql_replica
    restart: unless-stopped
    command: ["--default-authentication-plugin=mysql_native_password"]
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "${MYSQL_REPLICA_BIND_IP}:${MYSQL_REPLICA_PORT}:3306"
    volumes:
      - replica_data:/var/lib/mysql
      - ./docker/mysql/replica/my.cnf:/etc/mysql/conf.d/my.cnf:ro
    depends_on:
      mysql_primary:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: [sipv_net]

  web:
    build: .
    container_name: sipv_web
    restart: unless-stopped
    env_file: .env
    environment:
      DB_HOST: ${DB_HOST}
      DB_PORT: "${DB_PORT}"
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      DEBUG: "${DEBUG}"
      ALLOWED_HOSTS: "${ALLOWED_HOSTS}"
      SECRET_KEY: "${SECRET_KEY}"
      LANGUAGE_CODE: "${LANGUAGE_CODE}"
      TIME_ZONE: "${TIME_ZONE}"
      DJANGO_SUPERUSER_USERNAME: "${DJANGO_SUPERUSER_USERNAME}"
      DJANGO_SUPERUSER_EMAIL: "${DJANGO_SUPERUSER_EMAIL}"
      DJANGO_SUPERUSER_PASSWORD: "${DJANGO_SUPERUSER_PASSWORD}"
    depends_on:
      mysql_primary:
        condition: service_healthy
    ports:
      - "${WEB_BIND_IP}:${WEB_PORT}:8000"
    entrypoint: ["./docker/entrypoint.sh"]
    command: ["gunicorn", "backend.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "${GUNICORN_WORKERS}"]
    networks: [sipv_net]

  adminer:
    image: adminer:latest
    container_name: adminer
    restart: unless-stopped
    depends_on:
      mysql_primary:
        condition: service_healthy
    ports:
      - "${ADMINER_BIND_IP}:${ADMINER_PORT}:8080"
    networks: [sipv_net]

volumes:
  primary_data:
  replica_data:

networks:
  sipv_net:
    driver: bridge
EOF
}

compose_cmd() {
  local mode="${SIPV_MODE:-dev}"
  if [[ "$mode" == "prod" ]]; then
    echo "docker compose --env-file ${ENV_FILE} -f ${COMPOSE_PROD}"
  else
    echo "docker compose --env-file ${ENV_FILE} -f ${COMPOSE_DEV}"
  fi
}

wait_for_mysql_primary_healthy() {
  local c="mysql_primary"
  log "Esperando MySQL Primary healthy..."
  for i in {1..60}; do
    if docker inspect --format '{{json .State.Health.Status}}' "$c" 2>/dev/null | grep -q '"healthy"'; then
      log "MySQL Primary está healthy."
      return 0
    fi
    sleep 2
  done
  docker logs "$c" || true
  die "MySQL Primary no llegó a healthy."
}

mysql_root_probe() {
  docker exec -i mysql_primary mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1
}

mysql_root_probe_output() {
  docker exec -i mysql_primary mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1 || true
}

mysql_autofix_root_1045() {
  local cmd
  cmd="$(compose_cmd)"

  warn "MySQL root auth falló (ERROR 1045). Probable volumen previo con password distinto. Reinicializando MySQL (down -v)..."

  $cmd down -v --remove-orphans || true
  docker rm -f mysql_primary mysql_replica >/dev/null 2>&1 || true
  $cmd up -d mysql_primary mysql_replica

  wait_for_mysql_primary_healthy
}

ensure_mysql_db_user() {
  log "Asegurando DB/usuario/permisos en MySQL Primary..."

  local out
  out="$(mysql_root_probe_output)"

  if echo "$out" | grep -q "ERROR 1045"; then
    mysql_autofix_root_1045
  fi

  if ! mysql_root_probe; then
    err "No pude autenticar como root con MYSQL_ROOT_PASSWORD actual."
    err "Salida mysql (probe):"
    echo "$out" >&2
    docker logs --tail 200 mysql_primary || true
    die "Fallo al conectar como root. Revisa que no exista un volumen previo o que .env no cambie credenciales entre ejecuciones."
  fi

  docker exec -i mysql_primary mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

  log "DB y usuario verificados."
}

create_superuser_always() {
  log "Asegurando superuser de Django..."

  local cmd
  cmd="$(compose_cmd)"

  local settings_module="backend.settings"

  $cmd run --rm \
    -e DJANGO_SETTINGS_MODULE="${settings_module}" \
    -e DJANGO_SUPERUSER_USERNAME="${DJANGO_SUPERUSER_USERNAME}" \
    -e DJANGO_SUPERUSER_EMAIL="${DJANGO_SUPERUSER_EMAIL}" \
    -e DJANGO_SUPERUSER_PASSWORD="${DJANGO_SUPERUSER_PASSWORD}" \
    web bash -lc "python manage.py createsuperuser --noinput || true"

  $cmd run --rm \
    -e DJANGO_SETTINGS_MODULE="${settings_module}" \
    -e DJANGO_SUPERUSER_USERNAME="${DJANGO_SUPERUSER_USERNAME}" \
    -e DJANGO_SUPERUSER_EMAIL="${DJANGO_SUPERUSER_EMAIL}" \
    -e DJANGO_SUPERUSER_PASSWORD="${DJANGO_SUPERUSER_PASSWORD}" \
    web bash -lc "python - <<'PY'
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', os.environ.get('DJANGO_SETTINGS_MODULE','backend.settings'))

import django
django.setup()

from django.contrib.auth import get_user_model

User = get_user_model()
u = os.environ.get('DJANGO_SUPERUSER_USERNAME') or 'admin'
e = os.environ.get('DJANGO_SUPERUSER_EMAIL') or 'admin@local.com'
p = os.environ.get('DJANGO_SUPERUSER_PASSWORD') or None

obj = User.objects.filter(username=u).first()
if not obj:
    obj = User.objects.create(username=u, email=e)

obj.email = e
obj.is_staff = True
obj.is_superuser = True
if p:
    obj.set_password(p)
obj.save()

print('[superuser] listo:', u)
PY"
}

write_summary() {
  local private_ip public_ip app_host adminer_host
  private_ip="$(get_private_ip)"
  public_ip="$(get_public_ip || true)"

  if [[ "${WEB_BIND_IP:-0.0.0.0}" == "0.0.0.0" ]]; then
    app_host="${public_ip:-$private_ip}"
  else
    app_host="${WEB_BIND_IP}"
  fi

  if [[ "${ADMINER_BIND_IP:-127.0.0.1}" == "0.0.0.0" ]]; then
    adminer_host="${public_ip:-$private_ip}"
  else
    adminer_host="127.0.0.1"
  fi

  cat > "$SUMMARY_FILE" <<EOF
Instalacion completada

Proyecto: ${PROJECT_NAME}
Directorio: $(pwd)

Accesos:
- App:     http://${app_host}:${WEB_PORT}
- Adminer: http://${adminer_host}:${ADMINER_PORT}

IPs detectadas:
- IP privada: ${private_ip}
- IP publica: ${public_ip:-no disponible}

Credenciales:

MySQL Root
- Host: 127.0.0.1:${MYSQL_PRIMARY_PORT} (si MYSQL_PRIMARY_BIND_IP=127.0.0.1) o container mysql_primary
- Usuario: root
- Password: ${MYSQL_ROOT_PASSWORD}

Base de Datos (Django)
- DB_NAME: ${DB_NAME}
- DB_USER: ${DB_USER}
- DB_PASSWORD: ${DB_PASSWORD}
- DB_HOST (dentro de docker): ${DB_HOST}
- DB_PORT (dentro de docker): ${DB_PORT}

Django Admin (superuser)
- Username: ${DJANGO_SUPERUSER_USERNAME}
- Email:    ${DJANGO_SUPERUSER_EMAIL}
- Password: ${DJANGO_SUPERUSER_PASSWORD}

Notas:
- Este archivo contiene credenciales. Protegelo.
- Archivo de entorno: ${ENV_FILE}

Comandos utiles:
- Ver logs web:  $(compose_cmd) logs -f web
- Detener stack: $(compose_cmd) down
EOF

  chmod 600 "$SUMMARY_FILE" || true
}

print_summary() {
  echo
  echo "============================================================"
  echo "Instalacion completada"
  echo "============================================================"
  echo
  cat "$SUMMARY_FILE"
  echo
  echo "============================================================"
  echo "Resumen guardado en: $(pwd)/${SUMMARY_FILE}"
  echo "============================================================"
  echo
}

collectstatic_if_prod() {
  local mode="${SIPV_MODE:-dev}"
  [[ "$mode" == "prod" ]] || return 0

  log "Ejecutando collectstatic (prod)..."
  local cmd
  cmd="$(compose_cmd)"

  $cmd run --rm \
    -e DJANGO_SETTINGS_MODULE="backend.settings" \
    web bash -lc "python manage.py collectstatic --noinput || true"
}

apply_migrations() {
  log "Aplicando migraciones de Django..."

  local cmd
  cmd="$(compose_cmd)"

  $cmd run --rm \
    -e DJANGO_SETTINGS_MODULE="backend.settings" \
    web bash -lc "python manage.py migrate --noinput"
}

start_stack() {
  local cmd
  cmd="$(compose_cmd)"

  log "Build de imágenes..."
  $cmd build

  log "Levantando DBs primero..."
  $cmd up -d mysql_primary mysql_replica

  wait_for_mysql_primary_healthy
  ensure_mysql_db_user

  log "Levantando todo el stack..."
  $cmd up -d --force-recreate

  apply_migrations
  collectstatic_if_prod
  create_superuser_always

  write_summary
  print_summary
}

main() {
  local os
  os="$(detect_os)"
  case "$os" in
    ubuntu|debian) ;;
    *) warn "OS detectado: $os. Este script está pensado para Ubuntu/Debian." ;;
  esac

  install_base_packages
  ensure_repo_root_or_clone
  fix_dockerfile_if_needed

  write_env_example_if_missing
  bootstrap_env_if_missing
  ensure_env_has_generated_values
  load_env

  install_docker_if_missing
  ensure_docker_compose
  add_user_to_docker_group

  setup_ufw
  write_entrypoint_prod
  write_compose_files
  start_stack
}

main "$@"
