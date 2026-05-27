#!/usr/bin/env bash
# Crea un nuevo landing desde landing-template via GitHub API y lo clona localmente.
# Uso: bash create_landing.sh <slug> [base_dir]
# Ejemplo: bash create_landing.sh restaurante-el-prado
#
# Requiere: GITHUB_TOKEN con permisos repo + workflow en env o ~/.bashrc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../workspace.config.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq es requerido. Instálalo con: sudo apt install jq" >&2
  exit 1
fi
if ! command -v curl &>/dev/null; then
  echo "ERROR: curl es requerido." >&2
  exit 1
fi

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "Uso: bash create_landing.sh <slug> [base_dir]" >&2
  exit 1
fi

GITHUB_ORG=$(jq -r '.github_org' "$CONFIG")
BASE_DIR="${2:-$(jq -r '.base_dir' "$CONFIG")}"
BASE_DIR="${BASE_DIR/#\~/$HOME}"
REPO_NAME="landing-$SLUG"
DEST="$BASE_DIR/frontend-clients-ruta/$SLUG"

TOKEN="${GITHUB_TOKEN:-${NPM_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "ERROR: Define GITHUB_TOKEN (o NPM_TOKEN) con permisos repo." >&2
  exit 1
fi

echo "=== Creando landing $REPO_NAME en org $GITHUB_ORG ==="

# Crear repo desde template via GitHub API
HTTP_STATUS=$(curl -s -o /tmp/gh_create_response.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_ORG/landing-template/generate" \
  -d "{
    \"owner\": \"$GITHUB_ORG\",
    \"name\": \"$REPO_NAME\",
    \"description\": \"Landing custom — $SLUG\",
    \"private\": true,
    \"include_all_branches\": false
  }")

if [ "$HTTP_STATUS" != "201" ]; then
  echo "ERROR: GitHub API respondió $HTTP_STATUS" >&2
  cat /tmp/gh_create_response.json >&2
  exit 1
fi

echo "✅ Repo $REPO_NAME creado en GitHub"
echo "⏳ Esperando que GitHub inicialice el repo..."
sleep 3

# Clonar localmente
mkdir -p "$(dirname "$DEST")"
git clone "git@github.com:$GITHUB_ORG/$REPO_NAME.git" "$DEST"
echo ""
echo "✅ Landing listo en $DEST"
echo "   Próximo paso: cd $DEST && pnpm install && pnpm dev"
