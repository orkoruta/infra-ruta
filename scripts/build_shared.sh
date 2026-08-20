#!/usr/bin/env bash
# build_shared.sh
#
# Compila `@orkoruta/shared` (y opcionalmente `@orkoruta/db`) **sin pisar
# procesos que lo estén usando**.
#
# ¿Por qué hace falta un guard para un `tsc`? Porque en la estrategia
# local-first de Fase 3 los repos no consumen el paquete publicado: el
# `pnpm-workspace.yaml` lo enlaza con `link:../packages-ruta/shared`, así que
# el backend y los dos Next importan **directamente de `dist/`**. Recompilar
# reescribe esos ficheros debajo de cualquier proceso que ya los tenga
# abiertos, y el resultado es un módulo a medio cargar:
#
#   - En la suite de tests: falla **un test al azar de un fichero al azar**,
#     y al relanzar pasa. Es la causa real de los fallos intermitentes que se
#     achacaban a `vi.mock` y al paralelismo de vitest (comprobado el
#     2026-08-12: sin build concurrente, 9 corridas seguidas en verde; con
#     build concurrente, falló 2 de 4, una de ellas en `isolation.test.ts`,
#     uno de los ficheros de la lista original).
#   - En los dev servers de Next: `Cannot find module './7930.js'` o
#     `middleware-manifest.json`, y hay que reiniciarlos a mano.
#
# Uso:
#   bash infra-ruta/scripts/build_shared.sh          # aborta si hay procesos
#   bash infra-ruta/scripts/build_shared.sh --force  # compila igualmente
#   bash infra-ruta/scripts/build_shared.sh --db     # incluye @orkoruta/db

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGES_DIR="$REPO_ROOT/packages-ruta"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

FORCE=false
WITH_DB=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --db) WITH_DB=true ;;
    *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
  esac
done

# Procesos que están importando dist/ ahora mismo.
find_consumers() {
  local pid comm args
  # Solo PIDs: `pgrep -fl` imprime el comando entero, y uno que lleve un script
  # con saltos de línea dentro (un `zsh -c '…'`) rompe cualquier filtro por
  # líneas. Se resuelve cada PID por separado.
  for pid in $(pgrep -f 'vitest|next dev|next-server|tsx watch' 2>/dev/null); do
    [[ "$pid" == "$$" ]] && continue
    comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    [[ -z "$comm" ]] && continue
    # Un shell que solo *menciona* «vitest» en su línea de comando no está
    # usando dist/; sin esto el script se detecta a sí mismo.
    case "${comm##*/}" in
      zsh|bash|sh|dash|-zsh|-bash) continue ;;
    esac
    args="$(ps -p "$pid" -o args= 2>/dev/null | head -1 | cut -c 1-100)"
    printf '  %s  %s\n' "$pid" "$args"
  done
}

CONSUMERS="$(find_consumers)"

if [[ -n "$CONSUMERS" && "$FORCE" != true ]]; then
  echo -e "\n${RED}✗ No se compila: hay procesos usando dist/.${RESET}\n"
  echo "$CONSUMERS"
  echo -e "
${BOLD}Por qué se aborta:${RESET} estos procesos importan
'packages-ruta/shared/dist' a través del enlace del workspace. Recompilar
ahora les cambia los ficheros por debajo y provoca fallos que parecen
aleatorios: un test suelto que falla y al repetir pasa, o un dev server que
deja de resolver módulos.

${BOLD}Qué hacer:${RESET} para los tests, espera a que termine la suite. Para los
dev servers, párralos, compila y vuelve a arrancarlos.

Si sabes lo que haces:  bash infra-ruta/scripts/build_shared.sh --force
"
  exit 1
fi

if [[ -n "$CONSUMERS" ]]; then
  echo -e "${YELLOW}⚠ --force: se compila con procesos vivos. Reinícialos después.${RESET}"
fi

echo -e "${BOLD}Compilando @orkoruta/shared…${RESET}"
(cd "$PACKAGES_DIR" && pnpm --filter @orkoruta/shared build)

if [[ "$WITH_DB" == true ]]; then
  echo -e "${BOLD}Compilando @orkoruta/db…${RESET}"
  (cd "$PACKAGES_DIR" && pnpm --filter @orkoruta/db build)
fi

echo -e "${GREEN}✓${RESET} Listo."
