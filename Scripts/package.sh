#!/bin/bash
# Empaqueta la app para llevarla a otro Mac: la construye Xcode en Release para las dos
# arquitecturas, se firma ad-hoc y se comprime con ditto, que conserva el bundle como toca
# — un `zip` a secas estropea enlaces y permisos, y la firma deja de valer.
#
# En el Mac de destino hay que quitarle la cuarentena la primera vez, porque la app no está
# notarizada (notarizar necesita cuenta de desarrollador de pago). El zip lleva un LEEME.
set -euo pipefail
cd "$(dirname "$0")/.."

# Con -scheme y no -target: `-target` no resuelve las dependencias de paquete y la compilación
# muere con "unable to resolve module dependency: 'JSONCore'". Por eso el esquema está
# compartido en xcshareddata y no en xcuserdata, que no viaja en el repositorio.
DD="$PWD/build/DerivedData"
xcodebuild -project JsonToolingApp/JsonToolingApp.xcodeproj \
           -scheme JsonToolingApp \
           -configuration Release \
           -derivedDataPath "$DD" \
           ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
           build > /dev/null

APP="$DD/Build/Products/Release/JsonTooling.app"
[ -d "$APP" ] || { echo "no se generó $APP"; exit 1; }

codesign --force --sign - "$APP" 2>/dev/null || echo "aviso: no se pudo firmar"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

STAGE="build/JsonTooling"
OUT="build/JsonTooling-$(date +%Y%m%d).zip"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

cat > "$STAGE/LEEME.txt" <<'TXT'
JsonTooling

Para instalar:
  1. Arrastra JsonTooling.app a la carpeta Aplicaciones.
  2. Abre la Terminal y ejecuta:
       xattr -dr com.apple.quarantine /Applications/JsonTooling.app
  3. Ábrela normalmente.

El paso 2 hace falta porque la app no está notarizada por Apple (eso requiere una cuenta de
desarrollador de pago). Sin ese paso macOS dirá que no puede comprobar si contiene software
malicioso. Alternativa sin Terminal: clic derecho sobre la app > Abrir, y confirmar el aviso.

Para que abra los .json con doble clic: clic derecho en un .json > Obtener información >
Abrir con > JsonTooling > Cambiar todos.
TXT

ditto -c -k --keepParent --sequesterRsrc "$STAGE" "$OUT"
rm -rf "$STAGE"

echo "Listo: $OUT"
echo "  arquitecturas: $(lipo -archs "$APP/Contents/MacOS/JsonTooling")"
echo "  tamaño: $(du -h "$OUT" | cut -f1)"
