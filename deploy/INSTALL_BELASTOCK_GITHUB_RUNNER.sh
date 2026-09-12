#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/superamplitude/belastock"
SITE="/home/lojabelastock/htdocs/belastock.com.br"
SITE_USER="lojabelastock"
SITE_GROUP="lojabelastock"
RUNNER_USER="belastockrunner"
RUNNER_DIR="/opt/actions-runner-belastock"
RUNNER_NAME="belastock-prod-vps3565125"
RUNNER_LABEL="belastock-prod"
SUDOERS_FILE="/etc/sudoers.d/belastockrunner-bridge"
CONTROL_URL="https://raw.githubusercontent.com/superamplitude/belastock/main/deploy/BELASTOCK_VPS_CONTROL.sh"
CONTROL_DST="/usr/local/sbin/belastock-vps-control"

fail(){ echo "[ERRO] $*" >&2; exit 1; }
ok(){ echo "[OK] $*"; }

[ "${EUID}" -eq 0 ] || fail "Execute como root na VPS."
for cmd in curl python3 tar sudo visudo; do command -v "$cmd" >/dev/null 2>&1 || fail "$cmd nao encontrado."; done
getent passwd "$SITE_USER" >/dev/null 2>&1 || fail "Usuario $SITE_USER nao existe."
getent group "$SITE_GROUP" >/dev/null 2>&1 || fail "Grupo $SITE_GROUP nao existe."
[ -d "$SITE" ] || fail "Diretorio Bela Stock nao existe: $SITE"

TMP_CONTROL="$(mktemp)"
curl -fsSL --retry 3 --connect-timeout 15 "$CONTROL_URL" -o "$TMP_CONTROL"
bash -n "$TMP_CONTROL" || fail "Controlador baixado possui erro de sintaxe."
install -o root -g root -m 0755 "$TMP_CONTROL" "$CONTROL_DST"
rm -f "$TMP_CONTROL"
ok "Controle operacional Bela Stock instalado em $CONTROL_DST"

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUNNER_USER"
  ok "Usuario $RUNNER_USER criado"
fi
usermod -a -G "$SITE_GROUP" "$RUNNER_USER"

cat > "$SUDOERS_FILE" <<'EOF'
# Runner exclusivo do projeto Bela Stock.
# Pode operar como usuario dono do site e usar somente o controlador root do Bela Stock.
belastockrunner ALL=(lojabelastock) NOPASSWD: ALL
belastockrunner ALL=(root) NOPASSWD: /usr/local/sbin/belastock-vps-control, /usr/local/sbin/belastock-vps-control *
EOF
chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE" >/dev/null || fail "sudoers invalido."
sudo -u "$RUNNER_USER" sudo -n -u "$SITE_USER" true || fail "Runner nao consegue operar como $SITE_USER."
sudo -u "$RUNNER_USER" sudo -n "$CONTROL_DST" nginx-test >/dev/null || fail "Runner nao consegue usar controlador Bela Stock."
ok "Permissoes isoladas do runner configuradas"

TOKEN_INPUT="${1:-${BELASTOCK_RUNNER_TOKEN:-}}"
if [ -z "$TOKEN_INPUT" ]; then
  echo
  echo "Abra GitHub > superamplitude/belastock > Settings > Actions > Runners > New self-hosted runner > Linux x64."
  echo "Copie o token temporario ou a linha ./config.sh ... --token ... e cole abaixo."
  printf 'TOKEN/COMANDO: '
  IFS= read -r TOKEN_INPUT
fi
[ -n "$TOKEN_INPUT" ] || fail "Token vazio."

if [[ "$TOKEN_INPUT" == *"--token"* ]]; then
  RUNNER_TOKEN="$(python3 - "$TOKEN_INPUT" <<'PY'
import shlex, sys
parts=shlex.split(sys.argv[1])
try:
    print(parts[parts.index('--token')+1])
except Exception:
    pass
PY
)"
else
  RUNNER_TOKEN="$TOKEN_INPUT"
fi
RUNNER_TOKEN="$(printf '%s' "$RUNNER_TOKEN" | tr -d '\r\n[:space:]')"
[ "${#RUNNER_TOKEN}" -ge 20 ] || fail "Token invalido/curto. Gere um novo token em New runner."

mkdir -p "$RUNNER_DIR"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

if [ ! -x "$RUNNER_DIR/config.sh" ] || [ ! -x "$RUNNER_DIR/bin/Runner.Listener" ]; then
  LATEST_JSON="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)" || fail "Nao foi possivel consultar GitHub Actions Runner."
  RUNNER_VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' <<<"$LATEST_JSON")"
  [ -n "$RUNNER_VERSION" ] || fail "Versao do runner nao identificada."
  ARCHIVE="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}"
  TMP="/tmp/${ARCHIVE}"
  rm -rf "$RUNNER_DIR"/*
  curl -fL --retry 3 --retry-delay 2 "$URL" -o "$TMP"
  tar -xzf "$TMP" -C "$RUNNER_DIR"
  rm -f "$TMP"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
  ok "GitHub Actions Runner ${RUNNER_VERSION} instalado"
else
  ok "Binarios do GitHub Actions Runner ja existem"
fi

if [ -f "$RUNNER_DIR/.runner" ]; then
  ok "Runner ja registrado localmente"
else
  set +e
  sudo -u "$RUNNER_USER" -H bash -lc "cd '$RUNNER_DIR' && ./config.sh --unattended --replace --url '$REPO_URL' --token '$RUNNER_TOKEN' --name '$RUNNER_NAME' --labels '$RUNNER_LABEL' --work '_work'"
  RC=$?
  set -e
  unset RUNNER_TOKEN BELASTOCK_RUNNER_TOKEN TOKEN_INPUT
  [ "$RC" -eq 0 ] || fail "GitHub recusou o registro. Gere um novo token temporario."
  ok "Runner registrado no repositorio"
fi

cd "$RUNNER_DIR"
SERVICE_NAME="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '/actions\.runner\.superamplitude-belastock/{print $1; exit}')"
if [ -z "$SERVICE_NAME" ]; then
  ./svc.sh install "$RUNNER_USER"
fi
./svc.sh start >/dev/null 2>&1 || true
sleep 3
./svc.sh status

SERVICE_NAME="$(systemctl list-units --type=service --all --no-legend 2>/dev/null | awk '/actions\.runner\.superamplitude-belastock/{print $1; exit}')"
[ -n "$SERVICE_NAME" ] || fail "Servico runner nao localizado."
systemctl is-active --quiet "$SERVICE_NAME" || fail "Servico $SERVICE_NAME nao esta ativo."

sudo -u "$RUNNER_USER" -H sudo -n "$CONTROL_DST" status || true

printf '\n============================================================\n'
printf ' BELA STOCK GITHUB RUNNER CONECTADO\n'
printf '============================================================\n'
printf 'Repositorio: %s\n' "$REPO_URL"
printf 'Runner:      %s\n' "$RUNNER_NAME"
printf 'Label:       %s\n' "$RUNNER_LABEL"
printf 'Servico:     %s\n' "$SERVICE_NAME"
printf 'Usuario:     %s\n' "$RUNNER_USER"
printf 'Projeto:     %s\n' "$SITE"
printf 'Controle:    %s\n' "$CONTROL_DST"
printf 'Status:      ONLINE/ATIVO\n'
printf '============================================================\n'
