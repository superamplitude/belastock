#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

APP_DIR="/home/lojabelastock/htdocs/belastock.com.br"
APP_USER="lojabelastock"
APP_GROUP="lojabelastock"
DOMAIN="belastock.com.br"
STAMP="$(date +%Y%m%d_%H%M%S)"
SHORT="$(date +%m%d%H%M%S)"
BACKUP_DIR="/home/lojabelastock/backups/db-recovery-$STAMP"
RECOVERY_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/EXECUCAO_TOTAL_RECOVERY.sh"
RECOVERY_LOCAL="/root/EXECUCAO_TOTAL_RECOVERY.sh"

mkdir -p "$BACKUP_DIR"

fail(){
  local c=$?
  echo
  echo "============================================================"
  echo "BELA STOCK - FALHA NO RECOVERY RNL-STYLE"
  echo "codigo=$c linha=${BASH_LINENO[0]}"
  echo "backup=$BACKUP_DIR"
  echo "============================================================"
  exit "$c"
}
trap fail ERR

say(){ printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

[[ $EUID -eq 0 ]] || { echo "Execute como root"; exit 1; }
[[ -d "$APP_DIR" ]] || { echo "Diretorio ausente: $APP_DIR"; exit 2; }
[[ -f "$APP_DIR/.env" ]] || { echo ".env ausente: $APP_DIR/.env"; exit 3; }
command -v clpctl >/dev/null 2>&1 || { echo "clpctl ausente"; exit 4; }
command -v mysql >/dev/null 2>&1 || { echo "mysql client ausente"; exit 5; }
command -v openssl >/dev/null 2>&1 || { echo "openssl ausente"; exit 6; }

cp -a "$APP_DIR/.env" "$BACKUP_DIR/.env.before"
chmod 600 "$BACKUP_DIR/.env.before"

get_env(){ awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$APP_DIR/.env"; }
set_env(){
  local k="$1" v="$2"
  if grep -qE "^${k}=" "$APP_DIR/.env"; then
    sed -i "s#^${k}=.*#${k}=${v}#" "$APP_DIR/.env"
  else
    printf '%s=%s\n' "$k" "$v" >> "$APP_DIR/.env"
  fi
}

OLD_HOST="$(get_env DB_HOST)"; OLD_HOST="${OLD_HOST:-127.0.0.1}"
OLD_PORT="$(get_env DB_PORT)"; OLD_PORT="${OLD_PORT:-3306}"
OLD_DB="$(get_env DB_NAME)"
OLD_USER="$(get_env DB_USER)"
OLD_PASS="$(get_env DB_PASSWORD)"

printf '============================================================\n'
printf ' BELA STOCK - PROVISIONAMENTO DE BANCO ESTILO RNL\n'
printf ' %s\n' "$(date -Is)"
printf '============================================================\n'
printf 'Banco atual: %s\n' "${OLD_DB:-nao-configurado}"
printf 'Usuario atual: %s\n' "${OLD_USER:-nao-configurado}"
printf 'Senha: [OCULTA]\n'

CURRENT_OK=0
if [[ -n "$OLD_DB" && -n "$OLD_USER" ]]; then
  if MYSQL_PWD="$OLD_PASS" mysql -h "$OLD_HOST" -P "$OLD_PORT" -u "$OLD_USER" -NBe 'SELECT 1' "$OLD_DB" >/dev/null 2>&1; then
    CURRENT_OK=1
  fi
fi

if (( CURRENT_OK )); then
  say "Banco atual ja autentica; nenhuma troca de banco sera feita"
else
  say "Banco atual nao autentica. Preservando base antiga antes de provisionar nova"
  DUMP_FILE="$BACKUP_DIR/${OLD_DB:-belastock_antigo}.sql.gz"
  OLD_EXPORTED=0
  if [[ -n "$OLD_DB" ]]; then
    if clpctl db:export --databaseName="$OLD_DB" --file="$DUMP_FILE" >/dev/null 2>&1; then
      OLD_EXPORTED=1
      echo "Backup logico do banco antigo criado com sucesso."
    else
      echo "Aviso: CloudPanel nao conseguiu exportar o banco antigo. Ele NAO sera apagado nem alterado."
      rm -f "$DUMP_FILE"
    fi
  fi

  say "Criando banco e usuario NOVOS pelo CloudPanel, sem usar credencial master"
  NEW_DB="belastock_live_${SHORT}"
  NEW_USER="bs_${SHORT}"
  NEW_PASS="$(openssl rand -hex 24)"

  clpctl db:add \
    --domainName="$DOMAIN" \
    --databaseName="$NEW_DB" \
    --databaseUserName="$NEW_USER" \
    --databaseUserPassword="$NEW_PASS"

  if (( OLD_EXPORTED )); then
    say "Importando automaticamente os dados preservados para o banco novo"
    clpctl db:import --databaseName="$NEW_DB" --file="$DUMP_FILE"
  else
    say "Banco antigo indisponivel para exportacao; mantendo-o intacto e deixando migrations criarem a estrutura nova"
  fi

  say "Gravando novas credenciais dedicadas no .env"
  set_env DB_HOST 127.0.0.1
  set_env DB_PORT 3306
  set_env DB_NAME "$NEW_DB"
  set_env DB_USER "$NEW_USER"
  set_env DB_PASSWORD "$NEW_PASS"
  chown "$APP_USER:$APP_GROUP" "$APP_DIR/.env"
  chmod 640 "$APP_DIR/.env"

  say "Validando imediatamente o banco novo"
  MYSQL_PWD="$NEW_PASS" mysql -h 127.0.0.1 -P 3306 -u "$NEW_USER" -NBe 'SELECT 1' "$NEW_DB" >/dev/null
  echo "BANCO_NOVO_AUTENTICACAO=OK"
  echo "DB_NAME=$NEW_DB" > "$BACKUP_DIR/recovery-summary.txt"
  echo "DB_USER=$NEW_USER" >> "$BACKUP_DIR/recovery-summary.txt"
  echo "OLD_DB=${OLD_DB:-nao-configurado}" >> "$BACKUP_DIR/recovery-summary.txt"
  echo "OLD_DB_EXPORTADO=$OLD_EXPORTED" >> "$BACKUP_DIR/recovery-summary.txt"
  chmod 600 "$BACKUP_DIR/recovery-summary.txt"
fi

say "Executando recovery integral do Bela Stock sobre o banco ja funcional"
curl -fsSL --retry 3 --connect-timeout 15 "$RECOVERY_URL" -o "$RECOVERY_LOCAL"
chmod 700 "$RECOVERY_LOCAL"
exec bash "$RECOVERY_LOCAL"
