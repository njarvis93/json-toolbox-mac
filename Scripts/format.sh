#!/bin/bash
# Aplica el formato del proyecto. Lo mismo que comprueba el workflow "Formato", pero
# escribiendo los archivos en vez de solo avisar.
set -euo pipefail
cd "$(dirname "$0")/.."

xcrun swift-format format --in-place --configuration .swift-format --recursive \
    Sources Tests JsonToolingApp/JsonToolingApp JsonToolingApp/JsonToolingAppTests

echo "Formateado. Revisa el diff antes de commitear."
