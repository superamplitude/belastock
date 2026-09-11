#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

EXPECTED_SHA="deba72261bd1f63a5e525cb7903cecd80583a54089575602ba3af351768575b7"
EXPECTED_SIZE="36298"
PARTS_COMMIT="20fdd2c468e49f31b700b34ad421b15a0eb8c5dc"
INSTALLER_COMMIT="7169c030935535a4ba915cad1205ec3a67fbd2b2"
ROOT_ZIP="/root/BELASTOCK_NODE_V2_EXECUCAO_TOTAL.zip"
B64="/tmp/BELASTOCK_NODE_V2_EXECUCAO_TOTAL.b64"
INSTALLER="/root/EXECUCAO_TOTAL_VPS_CORE.sh"
BASE="https://raw.githubusercontent.com/superamplitude/belastock/${PARTS_COMMIT}/dist/v2-fixed"

echo "============================================================"
echo " BELA STOCK NODE 2.0 - EXECUCAO TOTAL V3"
echo " Reconstrucao e validacao do pacote integral"
echo "============================================================"

rm -f "$B64" "$ROOT_ZIP" "$INSTALLER"

for n in 00 01 02 03 04 05 06; do
  url="$BASE/part${n}.b64"
  echo "Baixando parte ${n}/06..."
  curl -fsSL --retry 3 --connect-timeout 15 "$url" >> "$B64"
done

base64 -d "$B64" > "$ROOT_ZIP"
ACTUAL_SIZE="$(stat -c '%s' "$ROOT_ZIP")"
ACTUAL_SHA="$(sha256sum "$ROOT_ZIP" | awk '{print $1}')"

echo "Pacote reconstruido: ${ACTUAL_SIZE} bytes"
echo "SHA256: ${ACTUAL_SHA}"

[[ "$ACTUAL_SIZE" == "$EXPECTED_SIZE" ]] || { echo "ERRO: tamanho do pacote diverge do esperado"; exit 61; }
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || { echo "ERRO: SHA256 do pacote diverge do esperado"; exit 62; }
unzip -tq "$ROOT_ZIP" >/dev/null || { echo "ERRO: ZIP reconstruido falhou no teste estrutural"; exit 63; }

echo "Pacote integral validado com sucesso."

curl -fsSL --retry 3 --connect-timeout 15 \
  "https://raw.githubusercontent.com/superamplitude/belastock/${INSTALLER_COMMIT}/deploy/EXECUCAO_TOTAL_VPS.sh" \
  -o "$INSTALLER"

# O instalador central continua verificando o mesmo SHA, mas recebe o artefato
# integral validado localmente em vez do antigo binario truncado do GitHub.
sed -i 's#^BUNDLE_URL=.*#BUNDLE_URL="file:///root/BELASTOCK_NODE_V2_EXECUCAO_TOTAL.zip"#' "$INSTALLER"
chmod +x "$INSTALLER"

exec bash "$INSTALLER"
