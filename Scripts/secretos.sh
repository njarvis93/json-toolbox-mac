#!/bin/bash
# Busca secretos en todo lo versionado, igual que el eslabón "Puerta" de CI.
#
#     ./Scripts/secretos.sh              comprueba
#     ./Scripts/secretos.sh --revisar    audita los hallazgos nuevos, uno a uno
#
# `.secrets.baseline` guarda lo ya revisado. Un hallazgo que no esté ahí hace fallar CI. Si es
# un falso positivo, `--revisar` lo marca; si es un secreto de verdad, hay que sacarlo del
# código **y rotarlo**, porque estar en el historial de git es estar publicado.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v detect-secrets > /dev/null || {
    echo "falta detect-secrets. Instálalo con: pip install detect-secrets"
    exit 1
}

if [ "${1:-}" = "--revisar" ]; then
    detect-secrets scan --baseline .secrets.baseline \
        --exclude-files '\.build/|build/|Assets\.xcassets/'
    detect-secrets audit .secrets.baseline
    echo "Línea base actualizada. Revisa el diff y commitéala."
    exit 0
fi

# El hook no reescribe la línea base: solo falla si aparece algo que no esté en ella.
detect-secrets-hook --baseline .secrets.baseline $(git ls-files)
echo "Sin secretos nuevos."
