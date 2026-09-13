#!/usr/bin/env bash
set -Eeuo pipefail
CONTROL="/usr/local/sbin/belastock-vps-control"
FILE="deploy/BELASTOCK_VPS_CONTROL.sh"

echo "============================================================"
echo " BELA STOCK - PM2 RESTART READINESS / CAUSA RAIZ"
echo " HOST=$(hostname)"
echo " DATE=$(date -Is)"
echo "============================================================"

sudo -n "$CONTROL" health
python3 - <<'PY'
from pathlib import Path
p=Path('deploy/BELASTOCK_VPS_CONTROL.sh')
s=p.read_text()
old='''  pm2-restart)
    pm2_user restart belastock --update-env
    pm2_user save
    restart_ok=0
    for i in $(seq 1 30); do
      if health_local >/dev/null 2>&1; then restart_ok=1; break; fi
      sleep 1
    done
    if [ "$restart_ok" != 1 ]; then
      pm2_user logs belastock --nostream --lines 120 || true
      fail "Aplicacao nao recuperou health apos restart PM2."
    fi
    health_local
    ;;'''
new='''  pm2-restart)
    pm2_user restart belastock --update-env
    pm2_user save
    restart_stable=0
    for i in $(seq 1 30); do
      if health_local >/dev/null 2>&1; then
        restart_stable=$((restart_stable + 1))
        if [ "$restart_stable" -ge 3 ]; then break; fi
      else
        restart_stable=0
      fi
      sleep 1
    done
    if [ "$restart_stable" -lt 3 ]; then
      pm2_user logs belastock --nostream --lines 120 || true
      fail "Aplicacao nao atingiu health estavel apos restart PM2."
    fi
    health_local
    ;;'''
if new in s:
    print('PM2_RESTART_STABLE_PATCH=ALREADY_PRESENT')
elif old in s:
    p.write_text(s.replace(old,new))
    print('PM2_RESTART_STABLE_PATCH=APPLIED')
else:
    raise SystemExit('first restart patch anchor not found')
PY
bash -n "$FILE"
git diff --check -- "$FILE"
grep -q 'restart_stable=0' "$FILE"

git config user.name 'Bela Stock Production Bridge'
git config user.email 'bridge@belastock.local'
git add "$FILE"
if git diff --cached --quiet; then
  echo "CONTROLLER_STABLE_RESTART_COMMIT=ALREADY_FIXED"
else
  git commit -m 'require stable health after PM2 restart'
  git push origin HEAD:main
  echo "CONTROLLER_STABLE_RESTART_COMMIT=PUSHED"
fi

sudo -n "$CONTROL" refresh-control
sudo -n "$CONTROL" pm2-restart
sudo -n "$CONTROL" health
systemctl is-active --quiet pm2-lojabelastock
systemctl is-enabled --quiet pm2-lojabelastock
echo "PM2_RESTART_RACE_ROOT_CAUSE=FIXED"
echo "PM2_RESTART_STABLE_HEALTH=100%_OK"
