#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
VHOST="/etc/nginx/sites-enabled/belastock.com.br.conf"
DEFAULT_PORT="3210"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/home/lojabelastock/backups/repair-502-$STAMP"
LOG_FILE="/root/BELASTOCK_REPAIR_502_${STAMP}.log"

mkdir -p "$BACKUP_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
  local code=$?
  echo
  echo "============================================================"
  echo "BELA STOCK - FALHA NA CORRECAO 502"
  echo "codigo=$code linha=${BASH_LINENO[0]}"
  echo "backup=$BACKUP_DIR"
  echo "log=$LOG_FILE"
  echo "============================================================"
  exit "$code"
}
trap fail ERR

[[ $EUID -eq 0 ]] || { echo "ERRO: execute como root."; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "ERRO: usuario $APP_USER nao existe."; exit 2; }
[[ -d "$APP_DIR" ]] || { echo "ERRO: diretorio da aplicacao nao existe: $APP_DIR"; exit 3; }
[[ -f "$APP_DIR/package.json" ]] || { echo "ERRO: package.json ausente em $APP_DIR"; exit 4; }
[[ -f "$APP_DIR/.env" ]] || { echo "ERRO: .env ausente em $APP_DIR"; exit 5; }

for cmd in nginx curl node npm sudo ss; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERRO: comando ausente: $cmd"; exit 6; }
done

if ! command -v pm2 >/dev/null 2>&1; then
  echo "PM2 ausente; instalando PM2 global..."
  npm install -g pm2@latest
fi

PM2_BIN="$(command -v pm2)"
NPM_BIN="$(command -v npm)"
PM2_HOME_DIR="/home/$APP_USER/.pm2"
[[ -x "$PM2_BIN" ]] || { echo "ERRO: binario PM2 nao executavel: $PM2_BIN"; exit 7; }
[[ -x "$NPM_BIN" ]] || { echo "ERRO: binario npm nao executavel: $NPM_BIN"; exit 8; }
install -d -m 750 -o "$APP_USER" -g "$APP_GROUP" "$PM2_HOME_DIR"

pm2_user() {
  sudo -u "$APP_USER" -H env PM2_HOME="$PM2_HOME_DIR" "$PM2_BIN" "$@"
}

PORT_FROM_ENV="$(awk -F= '/^PORT=/{print $2}' "$APP_DIR/.env" | tail -1 | tr -d '[:space:]\r\n')"
if [[ "$PORT_FROM_ENV" =~ ^[0-9]{2,5}$ ]]; then
  APP_PORT="$PORT_FROM_ENV"
else
  APP_PORT="$DEFAULT_PORT"
  echo "AVISO: PORT invalida/ausente no .env; usando porta oficial $DEFAULT_PORT."
fi

echo "============================================================"
echo "BELA STOCK - CORRECAO TOTAL DO 502"
echo "data=$(date -Is)"
echo "app=$APP_DIR"
echo "porta=$APP_PORT"
echo "vhost=$VHOST"
echo "pm2=$PM2_BIN"
echo "pm2_home=$PM2_HOME_DIR"
echo "============================================================"

# Evidencias antes de alterar qualquer coisa.
[[ -f "$VHOST" ]] && cp -a "$VHOST" "$BACKUP_DIR/belastock.com.br.conf.before"
cp -a "$APP_DIR/package.json" "$BACKUP_DIR/package.json"
[[ -f "$APP_DIR/ecosystem.config.cjs" ]] && cp -a "$APP_DIR/ecosystem.config.cjs" "$BACKUP_DIR/ecosystem.config.cjs"
nginx -T > "$BACKUP_DIR/nginx-T.before.txt" 2>&1 || true
ss -lntp > "$BACKUP_DIR/ports.before.txt" 2>&1 || true
pm2_user jlist > "$BACKUP_DIR/pm2.before.json" 2>/dev/null || true
pm2_user logs belastock --nostream --lines 120 > "$BACKUP_DIR/pm2.before.log" 2>&1 || true

health_ok() {
  curl -fsS --connect-timeout 3 --max-time 8 "http://127.0.0.1:${APP_PORT}/health" >/tmp/belastock-health.json 2>/dev/null
}

if health_ok; then
  echo "Aplicacao ja responde localmente em 127.0.0.1:${APP_PORT}."
else
  echo "Aplicacao nao responde em 127.0.0.1:${APP_PORT}; reiniciando processo Node."
  cd "$APP_DIR"

  # Nao altera codigo, banco ou .env. Corrige somente runtime/processo.
  if [[ ! -d node_modules ]]; then
    echo "node_modules ausente; instalando dependencias de producao."
    npm install --omit=dev
  fi

  chown "$APP_USER:$APP_GROUP" "$APP_DIR/.env"
  chmod 640 "$APP_DIR/.env"

  pm2_user delete belastock >/dev/null 2>&1 || true
  if [[ -f "$APP_DIR/ecosystem.config.cjs" ]]; then
    pm2_user start ecosystem.config.cjs
  else
    echo "ecosystem.config.cjs ausente; iniciando pelo script npm start via PM2."
    pm2_user start "$NPM_BIN" --name belastock -- start
  fi
  pm2_user save
  "$PM2_BIN" startup systemd -u "$APP_USER" --hp "/home/$APP_USER" >/dev/null 2>&1 || true

  for i in {1..30}; do
    if health_ok; then
      break
    fi
    sleep 1
  done

  if ! health_ok; then
    echo "ERRO: Node continuou sem responder apos reinicio."
    pm2_user status || true
    pm2_user logs belastock --nostream --lines 160 || true
    ss -lntp | grep -E ":${APP_PORT}[[:space:]]" || true
    exit 20
  fi
fi

cat /tmp/belastock-health.json || true
echo

# So troca o vhost depois de comprovar que o Node esta vivo.
[[ -f /etc/nginx/ssl-certificates/belastock.com.br.crt ]] || { echo "ERRO: certificado SSL ausente."; exit 21; }
[[ -f /etc/nginx/ssl-certificates/belastock.com.br.key ]] || { echo "ERRO: chave SSL ausente."; exit 22; }

TMP_VHOST="${VHOST}.repair-${STAMP}"
cat > "$TMP_VHOST" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name belastock.com.br www.belastock.com.br;
    return 301 https://belastock.com.br\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name www.belastock.com.br;

    ssl_certificate /etc/nginx/ssl-certificates/belastock.com.br.crt;
    ssl_certificate_key /etc/nginx/ssl-certificates/belastock.com.br.key;

    return 301 https://belastock.com.br\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name belastock.com.br;

    ssl_certificate /etc/nginx/ssl-certificates/belastock.com.br.crt;
    ssl_certificate_key /etc/nginx/ssl-certificates/belastock.com.br.key;

    access_log /home/lojabelastock/logs/nginx/access.log main;
    error_log /home/lojabelastock/logs/nginx/error.log;
    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
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

cp "$TMP_VHOST" "$VHOST"
rm -f "$TMP_VHOST"

if ! nginx -t; then
  echo "Nginx rejeitou o vhost novo; restaurando configuracao anterior."
  if [[ -f "$BACKUP_DIR/belastock.com.br.conf.before" ]]; then
    cp -a "$BACKUP_DIR/belastock.com.br.conf.before" "$VHOST"
    nginx -t
  fi
  exit 23
fi

systemctl reload nginx
sleep 2

LOCAL_CODE="$(curl -sS -o "$BACKUP_DIR/local-health.json" -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/health" || true)"
ORIGIN_HEALTH_CODE="$(curl -k -sS -o "$BACKUP_DIR/origin-health.json" -w '%{http_code}' --resolve belastock.com.br:443:127.0.0.1 https://belastock.com.br/health || true)"
ORIGIN_ROOT_CODE="$(curl -k -sS -o "$BACKUP_DIR/origin-root.html" -w '%{http_code}' --resolve belastock.com.br:443:127.0.0.1 https://belastock.com.br/ || true)"

pm2_user status belastock || true
ss -lntp | grep -E ":${APP_PORT}[[:space:]]" || true

printf '\n============================================================\n'
printf 'BELA STOCK - RESULTADO DA CORRECAO 502\n'
printf 'Local /health: %s\n' "$LOCAL_CODE"
printf 'Origin HTTPS /health: %s\n' "$ORIGIN_HEALTH_CODE"
printf 'Origin HTTPS /: %s\n' "$ORIGIN_ROOT_CODE"
printf 'Porta Node: %s\n' "$APP_PORT"
printf 'Backup: %s\n' "$BACKUP_DIR"
printf 'Log: %s\n' "$LOG_FILE"
printf '============================================================\n'

if [[ "$LOCAL_CODE" != "200" || "$ORIGIN_HEALTH_CODE" != "200" ]]; then
  echo "ERRO: a origem ainda nao esta saudavel. Nenhum ajuste de Cloudflare deve ser feito antes de corrigir isto."
  exit 24
fi

if [[ "$ORIGIN_ROOT_CODE" =~ ^(200|301|302)$ ]]; then
  echo "CORRECAO_502_BELASTOCK=CONCLUIDA"
else
  echo "ATENCAO: /health esta OK, mas a pagina inicial retornou HTTP $ORIGIN_ROOT_CODE."
  exit 25
fi
