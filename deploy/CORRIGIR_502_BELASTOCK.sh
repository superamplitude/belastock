#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
WWW_DOMAIN="www.belastock.com.br"
APP_PORT="3210"
EXPECTED_IP="162.35.104.133"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
SSL_CRT="/etc/nginx/ssl-certificates/belastock.com.br.crt"
SSL_KEY="/etc/nginx/ssl-certificates/belastock.com.br.key"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/home/lojabelastock/backups/recovery-$STAMP"
LOG_FILE="/root/BELASTOCK_RECOVERY_${STAMP}.log"
PM2_SERVICE="/etc/systemd/system/pm2-${APP_USER}.service"

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
  local code=$?
  echo
  echo "============================================================"
  echo "BELA STOCK - EXECUCAO INTERROMPIDA"
  echo "codigo=$code linha=${BASH_LINENO[0]}"
  echo "backup=$BACKUP_DIR"
  echo "log=$LOG_FILE"
  echo "============================================================"
  exit "$code"
}
trap fail ERR

say(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

[[ $EUID -eq 0 ]] || { echo "ERRO: execute como root."; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "ERRO: usuario $APP_USER nao existe."; exit 2; }
[[ -d "$APP_DIR" ]] || { echo "ERRO: diretorio nao existe: $APP_DIR"; exit 3; }
[[ -f "$APP_DIR/package.json" ]] || { echo "ERRO: package.json ausente em $APP_DIR"; exit 4; }
[[ -f "$APP_DIR/.env" ]] || { echo "ERRO: .env ausente em $APP_DIR"; exit 5; }

say "Inventario e backup antes de qualquer alteracao"
[[ -f "$VHOST" ]] && cp -a "$VHOST" "$BACKUP_DIR/belastock.com.br.conf.before"
[[ -f "$PM2_SERVICE" ]] && cp -a "$PM2_SERVICE" "$BACKUP_DIR/pm2-service.before"
cp -a "$APP_DIR/.env" "$BACKUP_DIR/.env.before"
cp -a "$APP_DIR/package.json" "$BACKUP_DIR/package.json"
[[ -f "$APP_DIR/ecosystem.config.cjs" ]] && cp -a "$APP_DIR/ecosystem.config.cjs" "$BACKUP_DIR/ecosystem.config.cjs"
nginx -T > "$BACKUP_DIR/nginx-T.before.txt" 2>&1 || true
ss -lntup > "$BACKUP_DIR/ports.before.txt" 2>&1 || true

say "Garantindo ferramentas necessarias"
export DEBIAN_FRONTEND=noninteractive
NEED_APT=0
for cmd in curl nginx node npm sudo ss lsof mysql; do
  command -v "$cmd" >/dev/null 2>&1 || NEED_APT=1
done
if (( NEED_APT )); then
  apt-get update -qq
  apt-get install -y --no-install-recommends curl nginx nodejs npm sudo iproute2 lsof default-mysql-client ca-certificates >/dev/null
fi

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( NODE_MAJOR < 20 )); then
  say "Node.js $(node -v) abaixo do minimo. Atualizando para Node 20"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs >/dev/null
fi

if ! command -v pm2 >/dev/null 2>&1; then
  say "Instalando PM2"
  npm install -g pm2@latest >/dev/null
fi

NODE_BIN="$(command -v node)"
NPM_BIN="$(command -v npm)"
PM2_BIN="$(command -v pm2)"
PM2_HOME_DIR="/home/$APP_USER/.pm2"
install -d -m 750 -o "$APP_USER" -g "$APP_GROUP" "$PM2_HOME_DIR"

pm2_user(){ sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" "$PM2_BIN" "$@"; }
npm_user(){ sudo -u "$APP_USER" -H env HOME="/home/$APP_USER" "$NPM_BIN" "$@"; }

say "Normalizando configuracao oficial da aplicacao"
set_env(){
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$APP_DIR/.env"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$APP_DIR/.env"
  else
    printf '%s=%s\n' "$key" "$value" >> "$APP_DIR/.env"
  fi
}
set_env NODE_ENV production
set_env HOST 127.0.0.1
set_env PORT "$APP_PORT"
set_env APP_URL "https://$DOMAIN"
chown "$APP_USER:$APP_GROUP" "$APP_DIR/.env"
chmod 640 "$APP_DIR/.env"
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
find "$APP_DIR" -type d -exec chmod 750 {} +

say "Verificando conflito da porta $APP_PORT"
if ! curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:$APP_PORT/health" >/dev/null 2>&1; then
  LISTENER_PID="$(lsof -t -iTCP:$APP_PORT -sTCP:LISTEN 2>/dev/null | head -1 || true)"
  if [[ -n "$LISTENER_PID" ]]; then
    LISTENER_CWD="$(readlink -f "/proc/$LISTENER_PID/cwd" 2>/dev/null || true)"
    LISTENER_CMD="$(tr '\0' ' ' < "/proc/$LISTENER_PID/cmdline" 2>/dev/null || true)"
    if [[ "$LISTENER_CWD" == "$APP_DIR"* ]]; then
      echo "Encerrando processo antigo do proprio Bela Stock: PID=$LISTENER_PID"
      kill "$LISTENER_PID" || true
      sleep 2
    else
      echo "ERRO: porta $APP_PORT ocupada por outro processo."
      echo "PID=$LISTENER_PID CWD=$LISTENER_CWD CMD=$LISTENER_CMD"
      exit 30
    fi
  fi
fi

say "Reparando dependencias Node"
cd "$APP_DIR"
npm_user install --omit=dev

has_script(){ node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts['$1']?0:1)"; }
if has_script check; then
  say "Executando validacao interna npm run check"
  npm_user run check
fi

say "Validando banco configurado no .env"
DB_HOST="$(awk -F= '/^DB_HOST=/{sub(/^DB_HOST=/,"");print;exit}' "$APP_DIR/.env")"
DB_PORT="$(awk -F= '/^DB_PORT=/{sub(/^DB_PORT=/,"");print;exit}' "$APP_DIR/.env")"
DB_NAME="$(awk -F= '/^DB_NAME=/{sub(/^DB_NAME=/,"");print;exit}' "$APP_DIR/.env")"
DB_USER="$(awk -F= '/^DB_USER=/{sub(/^DB_USER=/,"");print;exit}' "$APP_DIR/.env")"
DB_PASS="$(awk -F= '/^DB_PASSWORD=/{sub(/^DB_PASSWORD=/,"");print;exit}' "$APP_DIR/.env")"
DB_PORT="${DB_PORT:-3306}"
if [[ -n "$DB_HOST" && -n "$DB_NAME" && -n "$DB_USER" ]]; then
  if ! MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe "SELECT 1" "$DB_NAME" >/dev/null 2>&1; then
    echo "ERRO: banco nao acessivel com as credenciais atuais do .env."
    echo "DB_HOST=$DB_HOST DB_PORT=$DB_PORT DB_NAME=$DB_NAME DB_USER=$DB_USER"
    exit 31
  fi
  MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -NBe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" > "$BACKUP_DIR/db-table-count.txt"
fi

if has_script migrate; then
  say "Executando migrations idempotentes"
  npm_user run migrate
fi

say "Recriando processo PM2 do Bela Stock com caminho absoluto"
pm2_user delete belastock >/dev/null 2>&1 || true
if [[ -f "$APP_DIR/ecosystem.config.cjs" ]]; then
  pm2_user start "$APP_DIR/ecosystem.config.cjs" --update-env
else
  if ! has_script start; then
    echo "ERRO: ecosystem.config.cjs ausente e package.json nao possui script start."
    exit 32
  fi
  pm2_user start "$NPM_BIN" --name belastock --cwd "$APP_DIR" -- start
fi
pm2_user save

say "Aguardando healthcheck local"
LOCAL_OK=0
for i in {1..40}; do
  if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:$APP_PORT/health" > "$BACKUP_DIR/health-local.json" 2>/dev/null; then
    LOCAL_OK=1
    break
  fi
  sleep 1
done
if (( ! LOCAL_OK )); then
  echo "ERRO: aplicacao nao respondeu em 127.0.0.1:$APP_PORT/health."
  pm2_user status || true
  pm2_user logs belastock --nostream --lines 200 || true
  ss -lntup | grep ":$APP_PORT" || true
  exit 33
fi

say "Criando inicializacao automatica do PM2 no boot"
cat > "$PM2_SERVICE" <<EOF
[Unit]
Description=PM2 process manager for $APP_USER
After=network.target mysql.service mariadb.service
Wants=network-online.target

[Service]
Type=forking
User=$APP_USER
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PATH=$(dirname "$NODE_BIN"):$(dirname "$NPM_BIN"):$(dirname "$PM2_BIN"):/usr/local/bin:/usr/bin:/bin
Environment=PM2_HOME=$PM2_HOME_DIR
PIDFile=$PM2_HOME_DIR/pm2.pid
Restart=on-failure
ExecStart=$PM2_BIN resurrect
ExecReload=$PM2_BIN reload all
ExecStop=$PM2_BIN kill

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "pm2-$APP_USER" >/dev/null

say "Validando SSL e preparando Nginx"
[[ -f "$SSL_CRT" ]] || { echo "ERRO: certificado SSL nao encontrado: $SSL_CRT"; exit 34; }
[[ -f "$SSL_KEY" ]] || { echo "ERRO: chave SSL nao encontrada: $SSL_KEY"; exit 35; }
install -d -m 750 -o "$APP_USER" -g "$APP_GROUP" "/home/$APP_USER/logs/nginx"

cat > "$VHOST.new" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN $WWW_DOMAIN;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $WWW_DOMAIN;
    ssl_certificate $SSL_CRT;
    ssl_certificate_key $SSL_KEY;
    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $DOMAIN;

    ssl_certificate $SSL_CRT;
    ssl_certificate_key $SSL_KEY;

    access_log /home/$APP_USER/logs/nginx/access.log main;
    error_log /home/$APP_USER/logs/nginx/error.log;
    client_max_body_size 25m;

    location = /cgi-sys/suspendedpage.cgi {
        return 301 https://$DOMAIN/;
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_read_timeout 90s;
        proxy_connect_timeout 10s;
    }
}
NGINX
cp "$VHOST.new" "$VHOST"
rm -f "$VHOST.new"

if ! nginx -t; then
  echo "Nginx rejeitou a configuracao. Restaurando vhost anterior."
  [[ -f "$BACKUP_DIR/belastock.com.br.conf.before" ]] && cp -a "$BACKUP_DIR/belastock.com.br.conf.before" "$VHOST"
  nginx -t || true
  exit 36
fi
systemctl reload nginx

say "Validacao ponta a ponta"
LOCAL_HEALTH="$(curl -sS -o "$BACKUP_DIR/local-health.final.json" -w '%{http_code}' "http://127.0.0.1:$APP_PORT/health" || true)"
ORIGIN_HEALTH="$(curl -k -sS -o "$BACKUP_DIR/origin-health.json" -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/health" || true)"
ORIGIN_HOME="$(curl -k -sS -o "$BACKUP_DIR/origin-home.html" -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" || true)"
OLD_CGI="$(curl -k -sS -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/cgi-sys/suspendedpage.cgi" || true)"
DIRECT_IP_HEALTH="$(curl -k -sS -o "$BACKUP_DIR/direct-ip-health.json" -w '%{http_code}' --resolve "$DOMAIN:443:$EXPECTED_IP" "https://$DOMAIN/health" || true)"
PUBLIC_HEALTH="$(curl -sS -o "$BACKUP_DIR/public-health.json" -w '%{http_code}' "https://$DOMAIN/health" || true)"
PUBLIC_HOME="$(curl -sS -o "$BACKUP_DIR/public-home.html" -w '%{http_code}' "https://$DOMAIN/" || true)"
PUBLIC_WWW="$(curl -sS -L -o /dev/null -w '%{http_code}' "https://$WWW_DOMAIN/" || true)"
DNS_V4="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true)"
APP_VERSION="$(node -p "require('$APP_DIR/package.json').version || 'sem-version'" 2>/dev/null || echo sem-version)"

pm2_user status || true
systemctl is-enabled "pm2-$APP_USER" || true
systemctl is-active nginx || true

printf '\n============================================================\n'
printf ' BELA STOCK - AUDITORIA FINAL\n'
printf '============================================================\n'
printf 'Versao app: %s\n' "$APP_VERSION"
printf 'Node: %s\n' "$(node -v)"
printf 'npm: %s\n' "$(npm -v)"
printf 'PM2: %s\n' "$($PM2_BIN -v)"
printf 'Porta: %s\n' "$APP_PORT"
printf 'Local /health: %s\n' "$LOCAL_HEALTH"
printf 'Origin /health: %s\n' "$ORIGIN_HEALTH"
printf 'Origin /: %s\n' "$ORIGIN_HOME"
printf 'Redirect cPanel antigo: %s\n' "$OLD_CGI"
printf 'Direto IP %s /health: %s\n' "$EXPECTED_IP" "$DIRECT_IP_HEALTH"
printf 'Publico /health: %s\n' "$PUBLIC_HEALTH"
printf 'Publico /: %s\n' "$PUBLIC_HOME"
printf 'Publico www: %s\n' "$PUBLIC_WWW"
printf 'DNS IPv4 observado: %s\n' "${DNS_V4:-nao-resolvido}"
printf 'Backup: %s\n' "$BACKUP_DIR"
printf 'Log: %s\n' "$LOG_FILE"
printf '============================================================\n'

if [[ "$LOCAL_HEALTH" != "200" || "$ORIGIN_HEALTH" != "200" || "$DIRECT_IP_HEALTH" != "200" ]]; then
  echo "RESULTADO=FALHA_ORIGIN"
  exit 40
fi

if [[ ! "$ORIGIN_HOME" =~ ^(200|301|302)$ ]]; then
  echo "RESULTADO=FALHA_HOME_ORIGIN"
  exit 41
fi

echo "ORIGIN_BELASTOCK=100%_OK"
if [[ "$PUBLIC_HEALTH" == "200" && "$PUBLIC_HOME" =~ ^(200|301|302)$ ]]; then
  echo "PUBLICO_BELASTOCK=100%_OK"
  echo "EXECUCAO_TOTAL_BELASTOCK=CONCLUIDA"
else
  echo "PUBLICO_BELASTOCK=AGUARDANDO_DNS_OU_CAMADA_EXTERNA"
  echo "A origem esta corrigida. Nao ha mais acao necessaria no Node/Nginx."
fi
