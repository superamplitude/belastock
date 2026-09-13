#!/usr/bin/env bash
set -Eeuo pipefail
CONTROL="/usr/local/sbin/belastock-vps-control"
FILE="deploy/BELASTOCK_VPS_CONTROL.sh"

echo "============================================================"
echo " BELA STOCK - CORRECAO DEFINITIVA DO PM2 RESTART RACE"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

sudo -n "$CONTROL" health
python3 - <<'PY'
from pathlib import Path
p=Path('deploy/BELASTOCK_VPS_CONTROL.sh')
s=p.read_text()
old='  pm2-restart) pm2_user restart belastock --update-env; pm2_user save; health_local ;;'
new='''  pm2-restart)\n    pm2_user restart belastock --update-env\n    pm2_user save\n    restart_ok=0\n    for i in $(seq 1 30); do\n      if health_local >/dev/null 2>&1; then restart_ok=1; break; fi\n      sleep 1\n    done\n    if [ "$restart_ok" != 1 ]; then\n      pm2_user logs belastock --nostream --lines 120 || true\n      fail "Aplicacao nao recuperou health apos restart PM2."\n    fi\n    health_local\n    ;;'''
if new in s:
    print('PM2_RESTART_PATCH=ALREADY_PRESENT')
elif old in s:
    p.write_text(s.replace(old,new))
    print('PM2_RESTART_PATCH=APPLIED')
else:
    raise SystemExit('pm2-restart anchor not found')
PY
bash -n "$FILE"
git diff --check -- "$FILE"
grep -q 'restart_ok=0' "$FILE"

git config user.name 'Bela Stock Production Bridge'
git config user.email 'bridge@belastock.local'
git add "$FILE"
if git diff --cached --quiet; then
  echo "CONTROLLER_REPO_COMMIT=ALREADY_FIXED"
else
  git commit -m 'fix PM2 restart health race at controller root cause'
  git push origin HEAD:main
  echo "CONTROLLER_REPO_COMMIT=PUSHED"
fi

# Atualiza o controlador instalado a partir do repositório já corrigido e prova o restart.
sudo -n "$CONTROL" refresh-control
sudo -n "$CONTROL" pm2-restart
sudo -n "$CONTROL" health
systemctl is-active --quiet pm2-lojabelastock
systemctl is-enabled --quiet pm2-lojabelastock
echo "PM2_RESTART_RACE_ROOT_CAUSE=FIXED"
echo "PM2_RESTART_POST_HEALTH=100%_OK"
