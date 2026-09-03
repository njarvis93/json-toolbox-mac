#!/bin/bash
# Cobertura de líneas de JSONCore.
#
#     ./Scripts/coverage.sh 80                      ejecuta los tests y exige un 80 %
#     ./Scripts/coverage.sh --informe cobertura.txt  solo calcula y guarda el informe
#     ./Scripts/coverage.sh 80 --desde cobertura.txt juzga un informe ya calculado
#
# Las dos últimas formas existen por la cadena de CI: el número se calcula en el job de tests,
# que es donde está el `.build`, y quien lo juzga es el de calidad. Pasar el informe (unos pocos
# kilobytes) entre jobs es mucho más barato que arrastrar todo `.build`.
#
# Va sobre el paquete y no sobre la app a propósito: la app son en su mayoría vistas de SwiftUI
# y paneles de AppKit que no se pueden ejecutar sin interfaz, así que un umbral ahí mediría lo
# que no importa. La lógica que puede romperse en silencio vive aquí.
set -euo pipefail
cd "$(dirname "$0")/.."

MINIMO=""
INFORME_SALIDA=""
INFORME_ENTRADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        --informe) INFORME_SALIDA="$2"; shift 2 ;;
        --desde)   INFORME_ENTRADA="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *)         MINIMO="$1"; shift ;;
    esac
done

if [ -n "$INFORME_ENTRADA" ]; then
    [ -f "$INFORME_ENTRADA" ] || { echo "no existe $INFORME_ENTRADA"; exit 1; }
    INFORME=$(cat "$INFORME_ENTRADA")
else
    # Se ejecutan siempre con cobertura, sin comprobar si ya hay datos: un `swift test` normal
    # anterior deja el .profdata desfasado y llvm-cov falla con "no coverage data found", que es
    # un error críptico para lo que en realidad es "los datos son de otra compilación".
    swift test --enable-code-coverage > /dev/null

    PROFDATA=$(find .build -name default.profdata | head -1)
    # El `-not -path "*dSYM*"` importa: dentro del bundle hay ficheros del dSYM que `find`
    # devuelve antes que el binario, y llvm-cov falla con "not recognized as a valid object file".
    BINARIO=$(find .build -path "*.xctest/Contents/MacOS/*" -type f -not -path "*dSYM*" -perm +111 | head -1)

    if [ -z "$PROFDATA" ] || [ -z "$BINARIO" ]; then
        echo "no se encontraron los datos de cobertura"
        exit 1
    fi

    # `-ignore-filename-regex` deja fuera los propios tests: medir la cobertura de los tests
    # infla la cifra y no dice nada.
    INFORME=$(xcrun llvm-cov report "$BINARIO" -instr-profile "$PROFDATA" \
        -ignore-filename-regex="(Tests|\.build)/")
fi

echo "$INFORME"

if [ -n "$INFORME_SALIDA" ]; then
    echo "$INFORME" > "$INFORME_SALIDA"
    echo ""
    echo "Informe guardado en $INFORME_SALIDA"
fi

# Sin mínimo no hay puerta: se ha pedido solo el informe.
[ -n "$MINIMO" ] || exit 0

# La columna 10 de la fila TOTAL es el porcentaje de líneas.
COBERTURA=$(echo "$INFORME" | awk '/^TOTAL/ { gsub(/%/, "", $10); print $10 }')

if [ -z "$COBERTURA" ]; then
    echo "no se pudo leer el porcentaje de la fila TOTAL"
    exit 1
fi

echo ""
echo "Cobertura de líneas de JSONCore: ${COBERTURA}% (mínimo exigido: ${MINIMO}%)"

# bc no viene en todas partes; la comparación se hace con awk.
if awk -v c="$COBERTURA" -v m="$MINIMO" 'BEGIN { exit !(c < m) }'; then
    echo "::error::La cobertura ${COBERTURA}% está por debajo del mínimo ${MINIMO}%"
    exit 1
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Cobertura de JSONCore: ${COBERTURA}%"
        echo ''
        echo '```'
        echo "$INFORME"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi
