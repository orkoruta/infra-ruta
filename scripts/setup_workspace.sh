#!/usr/bin/env bash
# Clona todos los repos base de RUTA en la estructura local correcta.
# Uso: bash setup_workspace.sh [base_dir]
# Ejemplo: bash setup_workspace.sh ~/projects/ruta

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../workspace.config.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq es requerido. Instálalo con: sudo apt install jq" >&2
  exit 1
fi

GITHUB_ORG=$(jq -r '.github_org' "$CONFIG")
BASE_DIR="${1:-$(jq -r '.base_dir' "$CONFIG")}"
BASE_DIR="${BASE_DIR/#\~/$HOME}"

echo "=== RUTA workspace setup ==="
echo "Org GitHub : $GITHUB_ORG"
echo "Destino    : $BASE_DIR"
echo ""

mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR/frontend-clients-ruta"

jq -c '.repos[]' "$CONFIG" | while read -r repo; do
  NAME=$(echo "$repo" | jq -r '.name')
  TARGET=$(echo "$repo" | jq -r '.target')
  DEST="$BASE_DIR/$TARGET"
  PARENT=$(dirname "$DEST")

  mkdir -p "$PARENT"

  if [ -d "$DEST/.git" ]; then
    echo "✓ $NAME  →  $TARGET  (ya existe, actualizando)"
    git -C "$DEST" pull --ff-only
  else
    echo "↓ Clonando $NAME  →  $TARGET"
    git clone "git@github.com:$GITHUB_ORG/$NAME.git" "$DEST"
  fi
done

echo ""
echo "✅ Workspace listo en $BASE_DIR"
